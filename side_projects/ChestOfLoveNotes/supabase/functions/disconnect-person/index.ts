import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";
import { claimServerNotificationEvent, sendPushToUser } from "../_shared/push.ts";

/**
 * Durable mutual disconnect.
 *
 * Previous bug: friendships row deleted, but friend_requests stayed 'accepted'.
 * get-friends reconcileAcceptedPairing then re-inserted the pair → Mandy returned.
 *
 * This handler:
 * 1) deletes the active friendship
 * 2) verifies zero active friendships remain for caller
 * 3) cancels accepted+pending requests for the pair
 * 4) writes my_person_pair_ends tombstone (blocks auto-recreate)
 * 5) returns verified_disconnected only when post-write query is empty
 */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    if (req.method !== "POST") throw new AppError("method_not_allowed", "POST required", 405);
    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const service = createServiceClient();

    const { data: friendships, error } = await service
      .from("friendships")
      .select("id, user_one_id, user_two_id")
      .or(`user_one_id.eq.${me},user_two_id.eq.${me}`);
    if (error) throw new AppError("fetch_failed", "Could not load connection.", 500);
    if (!friendships || friendships.length === 0) {
      throw new AppError("not_connected", "You are not connected with anyone.", 404);
    }
    // Delete ALL active rows for this user (guards reciprocal/duplicate legacy rows).
    const otherIds = new Set<string>();
    for (const row of friendships) {
      const otherId = row.user_one_id === me ? row.user_two_id : row.user_one_id;
      otherIds.add(String(otherId));
    }
    const ids = friendships.map((r) => r.id);
    const { error: delErr } = await service
      .from("friendships")
      .delete()
      .in("id", ids);
    if (delErr) {
      console.error(delErr);
      throw new AppError("disconnect_failed", "Could not disconnect.", 500);
    }

    const now = new Date().toISOString();
    for (const otherId of otherIds) {
      const pairOr =
        `and(sender_id.eq.${me},recipient_id.eq.${otherId}),and(sender_id.eq.${otherId},recipient_id.eq.${me})`;
      // Tombstone first so any concurrent path cannot re-insert this pair.
      const { error: tombErr } = await service.rpc("record_my_person_pair_end", {
        p_a: me,
        p_b: otherId,
        p_ended_by: me,
      });
      if (tombErr) {
        console.error("record_my_person_pair_end failed", tombErr);
        throw new AppError("disconnect_failed", "Could not disconnect.", 500);
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

    // Post-write verification — do not claim success if a row remains.
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
    });
  } catch (err) {
    return errorResponse(err);
  }
});
