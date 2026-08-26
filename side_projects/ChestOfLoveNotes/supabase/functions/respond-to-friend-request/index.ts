import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";
import { claimServerNotificationEvent, sendPushToUser } from "../_shared/push.ts";

interface Body {
  request_id: string;
  action: "accept" | "decline" | "cancel";
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const body = (await req.json()) as Body;
    requireFields(body, ["request_id", "action"]);

    if (!["accept", "decline", "cancel"].includes(body.action)) {
      throw new AppError("invalid_action", "action must be accept|decline|cancel", 400);
    }

    const service = createServiceClient();
    const { data: fr, error } = await service
      .from("friend_requests")
      .select("id, sender_id, recipient_id, status")
      .eq("id", body.request_id)
      .maybeSingle();

    if (error || !fr) {
      throw new AppError("not_found", "Connection request not found", 404);
    }
    if (fr.status !== "pending") {
      throw new AppError("not_pending", "Request is no longer pending", 409);
    }

    if (body.action === "cancel") {
      if (fr.sender_id !== me) {
        throw new AppError("forbidden", "Only the sender can cancel", 403);
      }
      const { data: updated, error: upErr } = await service
        .from("friend_requests")
        .update({
          status: "cancelled",
          responded_at: new Date().toISOString(),
        })
        .eq("id", fr.id)
        .select("id, status, responded_at")
        .single();
      if (upErr) throw new AppError("update_failed", "Could not cancel request", 500);
      return jsonResponse({ request: updated });
    }

    if (fr.recipient_id !== me) {
      throw new AppError("forbidden", "Only the recipient can respond", 403);
    }

    if (body.action === "decline") {
      const { data: updated, error: upErr } = await service
        .from("friend_requests")
        .update({
          status: "declined",
          responded_at: new Date().toISOString(),
        })
        .eq("id", fr.id)
        .select("id, status, responded_at")
        .single();
      if (upErr) throw new AppError("update_failed", "Could not decline request", 500);
      return jsonResponse({ request: updated });
    }

    // accept — both parties must still be free (transactional via DB trigger + unique indexes)
    const { data: iHave } = await service.rpc("has_active_person", { p_user: me });
    if (iHave) {
      throw new AppError(
        "already_has_person",
        "You're already connected with someone. Disconnect first if you want to connect with someone else.",
        409,
      );
    }
    const { data: theyHave } = await service.rpc("has_active_person", { p_user: fr.sender_id });
    if (theyHave) {
      throw new AppError(
        "target_has_person",
        "That person is already connected with someone else.",
        409,
      );
    }

    const { data: blocked } = await service.rpc("is_blocked", {
      a: fr.sender_id,
      b: fr.recipient_id,
    });
    if (blocked) {
      throw new AppError("blocked", "Cannot accept — a block exists", 403);
    }

    const userOne = fr.sender_id < fr.recipient_id ? fr.sender_id : fr.recipient_id;
    const userTwo = fr.sender_id < fr.recipient_id ? fr.recipient_id : fr.sender_id;

    // Explicit NEW accept may reconnect a previously disconnected pair.
    // Clear durable tombstone BEFORE insert (trigger blocks insert while present).
    const { error: clearEndErr } = await service.rpc("clear_my_person_pair_end", {
      p_a: fr.sender_id,
      p_b: fr.recipient_id,
    });
    if (clearEndErr) {
      console.warn("clear_my_person_pair_end", clearEndErr);
      // Continue — table may not exist until migration; insert may still succeed.
    }

    const { error: friendErr } = await service.from("friendships").insert({
      user_one_id: userOne,
      user_two_id: userTwo,
    });
    if (friendErr) {
      console.error(friendErr);
      const msg = String(friendErr.message ?? "");
      if (msg.includes("already_has_person") || friendErr.code === "23505") {
        throw new AppError(
          "already_has_person",
          "Only one Person connection is allowed.",
          409,
        );
      }
      if (msg.includes("pair_disconnected")) {
        throw new AppError(
          "pair_disconnected",
          "Could not connect. Please send a new connection request.",
          409,
        );
      }
      throw new AppError("friendship_failed", "Could not create connection", 500);
    }

    const { data: updated, error: upErr } = await service
      .from("friend_requests")
      .update({
        status: "accepted",
        responded_at: new Date().toISOString(),
      })
      .eq("id", fr.id)
      .select("id, status, responded_at")
      .single();
    if (upErr) throw new AppError("update_failed", "Could not accept request", 500);

    // Decline other pending requests involving either party (one-person model).
    await service
      .from("friend_requests")
      .update({ status: "declined", responded_at: new Date().toISOString() })
      .eq("status", "pending")
      .or(
        `sender_id.eq.${me},recipient_id.eq.${me},sender_id.eq.${fr.sender_id},recipient_id.eq.${fr.sender_id}`,
      )
      .neq("id", fr.id);

    const { data: meProfile } = await service
      .from("profiles")
      .select("display_name")
      .eq("id", me)
      .maybeSingle();
    const myName = String(meProfile?.display_name ?? "Your Person");
    if (await claimServerNotificationEvent(String(fr.sender_id), null, `conn_accept:${fr.id}`)) {
      await sendPushToUser(String(fr.sender_id), {
        title: "Connected",
        body: `You're now connected with ${myName}.`,
        deepLink: "person",
        channel: "connections",
      });
    }

    return jsonResponse({
      request: updated,
      friendship: { user_one_id: userOne, user_two_id: userTwo },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
