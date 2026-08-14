import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

interface Body {
  recipient_id?: string;
  friend_code?: string;
  message?: string;
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

    const service = createServiceClient();

    let recipientId = body.recipient_id?.trim();
    if (!recipientId && body.friend_code) {
      const code = body.friend_code.trim().toUpperCase();
      const { data: profile, error } = await service
        .from("profiles")
        .select("id")
        .eq("friend_code", code)
        .maybeSingle();
      if (error) throw new AppError("lookup_failed", "Could not look up friend code", 500);
      if (!profile) throw new AppError("not_found", "No user with that friend code", 404);
      recipientId = profile.id as string;
    }

    requireFields({ recipient_id: recipientId }, ["recipient_id"]);

    if (recipientId === me) {
      throw new AppError("invalid_request", "You cannot friend yourself", 400);
    }

    const { data: recipient, error: recipErr } = await service
      .from("profiles")
      .select("id")
      .eq("id", recipientId!)
      .maybeSingle();
    if (recipErr || !recipient) {
      throw new AppError("not_found", "Recipient profile not found", 404);
    }

    const { data: blocked } = await service.rpc("is_blocked", { a: me, b: recipientId });
    if (blocked) {
      throw new AppError("blocked", "Cannot send friend request", 403);
    }

    const { data: alreadyFriends } = await service.rpc("are_friends", {
      a: me,
      b: recipientId,
    });
    if (alreadyFriends) {
      throw new AppError("already_friends", "You are already friends", 409);
    }

    const { data: pending } = await service.rpc("pending_friend_request_exists", {
      a: me,
      b: recipientId,
    });
    if (pending) {
      throw new AppError("pending_exists", "A pending request already exists", 409);
    }

    const { data: row, error: insertErr } = await service
      .from("friend_requests")
      .insert({
        sender_id: me,
        recipient_id: recipientId,
        status: "pending",
        message: body.message?.slice(0, 280) ?? null,
      })
      .select("id, sender_id, recipient_id, status, created_at")
      .single();

    if (insertErr) {
      console.error(insertErr);
      throw new AppError("insert_failed", "Could not create friend request", 500);
    }

    return jsonResponse({ request: row });
  } catch (err) {
    return errorResponse(err);
  }
});
