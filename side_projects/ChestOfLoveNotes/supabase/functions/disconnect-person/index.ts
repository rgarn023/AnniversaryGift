import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient, createUserClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";
import { claimServerNotificationEvent, sendPushToUser } from "../_shared/push.ts";

/**
 * Durable mutual disconnect.
 *
 * Preferred path: PostgreSQL RPC disconnect_my_person() via the caller's JWT
 * (auth.uid()). That function is transactional and matches the canonical
 * friendships-based active-Person definition used by get-friends.
 *
 * Fallback (service role): inline delete + request cancel when the RPC is not
 * yet deployed. Tombstone helpers are best-effort — missing RPCs must NOT
 * abort after friendships were removed (v34 failure mode).
 */
function rpcMissing(err: { message?: string; code?: string } | null): boolean {
  if (!err) return false;
  const msg = String(err.message ?? "").toLowerCase();
  const code = String(err.code ?? "");
  return (
    code === "PGRST202" ||
    code === "42883" ||
    msg.includes("could not find the function") ||
    msg.includes("does not exist") ||
    msg.includes("schema cache")
  );
}

function categorizeRpcError(err: { message?: string; code?: string; details?: string } | null): string {
  if (!err) return "Unknown";
  const msg = String(err.message ?? "").toLowerCase();
  const code = String(err.code ?? "");
  if (rpcMissing(err)) return "RPC Missing";
  if (code === "42501" || msg.includes("permission") || msg.includes("rls")) return "RLS";
  if (code === "28000" || msg.includes("not authenticated")) return "Unauthorized";
  if (msg.includes("not_connected") || msg.includes("no row")) return "No Row";
  if (msg.includes("schema") || code.startsWith("42")) return "Schema";
  if (msg.includes("disconnect_verify") || msg.includes("pair_disconnected")) return "Function Error";
  return "Function Error";
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    if (req.method !== "POST") throw new AppError("method_not_allowed", "POST required", 405);
    const { user, authHeader } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);

    // --- Preferred: atomic auth.uid() RPC (same identity as REST client path) ---
    const userClient = createUserClient(authHeader);
    const { data: rpcData, error: rpcErr } = await userClient.rpc("disconnect_my_person");
    if (!rpcErr && rpcData && typeof rpcData === "object") {
      const payload = rpcData as Record<string, unknown>;
      const success = payload.success === true || payload.verified_disconnected === true;
      const found = payload.relationship_found === true;
      if (!success) {
        throw new AppError(
          String(payload.error_code ?? "not_connected"),
          found
            ? "Could not disconnect."
            : "You are not connected with anyone.",
          found ? 500 : 404,
        );
      }

      // Best-effort notify: resolve former peer via get_active_person_id is impossible
      // after delete. Peer notification is optional and skipped on RPC path.
      return jsonResponse({
        ok: true,
        verified_disconnected: true,
        person: null,
        active_pairing: false,
        relationship_status: "disconnected",
        relationship_found: true,
        disconnected: true,
        rows_affected: Number(payload.rows_affected ?? 1),
        disconnect_mechanism: "RPC",
        failure_category: "None",
        active_pair_found: true,
      });
    }

    if (rpcErr && !rpcMissing(rpcErr)) {
      console.error("disconnect_my_person failed", {
        code: rpcErr.code,
        message: rpcErr.message,
        category: categorizeRpcError(rpcErr),
      });
      throw new AppError(
        "disconnect_failed",
        "Could not disconnect.",
        500,
      );
    }

    // --- Fallback: service-role inline (RPC not deployed yet) ---
    console.warn("disconnect_my_person RPC unavailable; using service-role fallback");
    const service = createServiceClient();

    const { data: friendships, error } = await service
      .from("friendships")
      .select("id, user_one_id, user_two_id")
      .or(`user_one_id.eq.${me},user_two_id.eq.${me}`);
    if (error) throw new AppError("fetch_failed", "Could not load connection.", 500);
    if (!friendships || friendships.length === 0) {
      throw new AppError("not_connected", "You are not connected with anyone.", 404);
    }

    const otherIds = new Set<string>();
    for (const row of friendships) {
      const otherId = row.user_one_id === me ? row.user_two_id : row.user_one_id;
      otherIds.add(String(otherId));
    }
    const ids = friendships.map((r) => r.id);
    const now = new Date().toISOString();

    // Tombstone + cancel BEFORE delete so a mid-flight failure cannot leave
    // deleted friendships with still-accepted requests (auto-reconnect fuel),
    // and so missing tombstone helpers do not abort after a destructive delete.
    for (const otherId of otherIds) {
      const pairOr =
        `and(sender_id.eq.${me},recipient_id.eq.${otherId}),and(sender_id.eq.${otherId},recipient_id.eq.${me})`;

      const { error: tombErr } = await service.rpc("record_my_person_pair_end", {
        p_a: me,
        p_b: otherId,
        p_ended_by: me,
      });
      if (tombErr) {
        if (rpcMissing(tombErr)) {
          // Direct insert if table exists; ignore if table missing.
          const u1 = me < otherId ? me : otherId;
          const u2 = me < otherId ? otherId : me;
          const { error: insErr } = await service.from("my_person_pair_ends").upsert({
            user_one_id: u1,
            user_two_id: u2,
            ended_by: me,
            disconnected_at: now,
          });
          if (insErr) {
            console.warn("tombstone unavailable; continuing with request cancel + delete", {
              code: insErr.code,
              message: insErr.message,
            });
          }
        } else {
          console.error("record_my_person_pair_end failed", tombErr);
          throw new AppError("disconnect_failed", "Could not disconnect.", 500);
        }
      }

      const { error: cancelAcceptedErr } = await service
        .from("friend_requests")
        .update({ status: "cancelled", responded_at: now })
        .eq("status", "accepted")
        .or(pairOr);
      if (cancelAcceptedErr) {
        console.error("disconnect cancel accepted failed", cancelAcceptedErr);
        throw new AppError("disconnect_failed", "Could not disconnect.", 500);
      }
      const { error: cancelPendingErr } = await service
        .from("friend_requests")
        .update({ status: "cancelled", responded_at: now })
        .eq("status", "pending")
        .or(pairOr);
      if (cancelPendingErr) {
        console.error("disconnect cancel pending failed", cancelPendingErr);
        throw new AppError("disconnect_failed", "Could not disconnect.", 500);
      }
    }

    const { error: delErr, count: delCount } = await service
      .from("friendships")
      .delete({ count: "exact" })
      .in("id", ids);
    if (delErr) {
      console.error(delErr);
      throw new AppError("disconnect_failed", "Could not disconnect.", 500);
    }
    if (!delCount || delCount < 1) {
      console.error("disconnect_rows_affected=0");
      throw new AppError("disconnect_failed", "Could not disconnect.", 500);
    }

    const { data: still, error: stillErr } = await service
      .from("friendships")
      .select("id")
      .or(`user_one_id.eq.${me},user_two_id.eq.${me}`)
      .limit(1);
    if (stillErr) {
      throw new AppError("disconnect_failed", "Could not verify disconnect.", 500);
    }
    if (still && still.length > 0) {
      throw new AppError("disconnect_failed", "Could not disconnect.", 500);
    }
    const { data: stillActive } = await service.rpc("has_active_person", { p_user: me });
    if (stillActive) {
      throw new AppError("disconnect_failed", "Could not disconnect.", 500);
    }

    const { data: meProfile } = await service
      .from("profiles")
      .select("display_name")
      .eq("id", me)
      .maybeSingle();
    const name = String(meProfile?.display_name ?? "Your Person");
    for (const otherId of otherIds) {
      if (await claimServerNotificationEvent(String(otherId), null, `disconnect:${ids[0]}:${otherId}`)) {
        await sendPushToUser(String(otherId), {
          title: "Connection ended",
          body: `You're no longer connected with ${name}.`,
          deepLink: "person",
          channel: "connections",
        });
      }
    }

    return jsonResponse({
      ok: true,
      verified_disconnected: true,
      person: null,
      active_pairing: false,
      relationship_status: "disconnected",
      relationship_found: true,
      disconnected: true,
      rows_affected: delCount,
      disconnect_mechanism: "Edge Function",
      failure_category: "None",
      active_pair_found: true,
    });
  } catch (err) {
    return errorResponse(err);
  }
});
