import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";
import { claimServerNotificationEvent, sendPushToUser } from "../_shared/push.ts";

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
    const f = friendships[0];
    const otherId = f.user_one_id === me ? f.user_two_id : f.user_one_id;

    const { data: meProfile } = await service
      .from("profiles")
      .select("display_name")
      .eq("id", me)
      .maybeSingle();

    const { error: delErr } = await service.from("friendships").delete().eq("id", f.id);
    if (delErr) {
      console.error(delErr);
      throw new AppError("disconnect_failed", "Could not disconnect.", 500);
    }

    // Durable disconnect tombstone: cancel accepted/pending requests for this pair.
    // Without this, get-friends reconcileAcceptedPairing rehydrates the friendship
    // from leftover friend_requests.status='accepted' and auto-reconnects.
    const now = new Date().toISOString();
    const pairOr =
      `and(sender_id.eq.${me},recipient_id.eq.${otherId}),and(sender_id.eq.${otherId},recipient_id.eq.${me})`;
    const { error: cancelAcceptedErr } = await service
      .from("friend_requests")
      .update({ status: "cancelled", responded_at: now })
      .eq("status", "accepted")
      .or(pairOr);
    if (cancelAcceptedErr) {
      console.error("disconnect cancel accepted requests failed", cancelAcceptedErr);
      throw new AppError("disconnect_failed", "Could not disconnect.", 500);
    }
    const { error: cancelPendingErr } = await service
      .from("friend_requests")
      .update({ status: "cancelled", responded_at: now })
      .eq("status", "pending")
      .or(pairOr);
    if (cancelPendingErr) {
      console.error("disconnect cancel pending requests failed", cancelPendingErr);
      // Friendship already removed; still treat as disconnected but log.
    }

    // Optional notify other party (privacy-safe).
    const name = String(meProfile?.display_name ?? "Your Person");
    if (await claimServerNotificationEvent(String(otherId), null, `disconnect:${f.id}`)) {
      await sendPushToUser(String(otherId), {
        title: "Connection ended",
        body: `You're no longer connected with ${name}.`,
        deepLink: "person",
        channel: "connections",
      });
    }

    return jsonResponse({ ok: true, disconnected_from: otherId });
  } catch (err) {
    return errorResponse(err);
  }
});
