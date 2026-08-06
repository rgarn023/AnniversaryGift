import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

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
      throw new AppError("not_found", "Friend request not found", 404);
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

    // accept / decline — recipient only
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

    // accept → mark accepted + create normalized friendship
    const { data: blocked } = await service.rpc("is_blocked", {
      a: fr.sender_id,
      b: fr.recipient_id,
    });
    if (blocked) {
      throw new AppError("blocked", "Cannot accept — a block exists", 403);
    }

    const userOne = fr.sender_id < fr.recipient_id ? fr.sender_id : fr.recipient_id;
    const userTwo = fr.sender_id < fr.recipient_id ? fr.recipient_id : fr.sender_id;

    const { error: friendErr } = await service.from("friendships").upsert(
      { user_one_id: userOne, user_two_id: userTwo },
      { onConflict: "user_one_id,user_two_id", ignoreDuplicates: true },
    );
    if (friendErr) {
      console.error(friendErr);
      throw new AppError("friendship_failed", "Could not create friendship", 500);
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

    return jsonResponse({
      request: updated,
      friendship: { user_one_id: userOne, user_two_id: userTwo },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
