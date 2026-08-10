import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";
import { claimServerNotificationEvent, sendPushToUser } from "../_shared/push.ts";

interface Body {
  recipient_id?: string;
  friend_code?: string;
  connection_token?: string;
  message?: string;
}

function extractToken(raw: string): string {
  let t = raw.trim();
  const m = t.match(/(?:chestoflovenotes:\/\/connect\/|\/connect\/)([A-Za-z0-9_-]+)/i);
  if (m) t = m[1];
  return t.trim().toLowerCase();
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

    // Sender must not already have an active Person.
    const { data: iHavePerson } = await service.rpc("has_active_person", { p_user: me });
    if (iHavePerson) {
      throw new AppError(
        "already_has_person",
        "You're already connected with someone. Disconnect first if you want to connect with someone else.",
        409,
      );
    }

    let recipientId = body.recipient_id?.trim();
    if (!recipientId && body.connection_token) {
      const token = extractToken(body.connection_token);
      const { data: rows, error } = await service.rpc("resolve_connection_token", { p_token: token });
      if (error) throw new AppError("lookup_failed", "Could not look up connection code", 500);
      const row = Array.isArray(rows) ? rows[0] : rows;
      if (!row?.id) {
        throw new AppError("not_found", "This isn't a valid Chest of Love Notes connection code.", 404);
      }
      recipientId = String(row.id);
    }
    if (!recipientId && body.friend_code) {
      const code = body.friend_code.trim().toUpperCase();
      const { data: profile, error } = await service
        .from("profiles")
        .select("id")
        .eq("friend_code", code)
        .maybeSingle();
      if (error) throw new AppError("lookup_failed", "Could not look up connection code", 500);
      if (!profile) throw new AppError("not_found", "No user with that connection code", 404);
      recipientId = profile.id as string;
    }

    requireFields({ recipient_id: recipientId }, ["recipient_id"]);

    if (recipientId === me) {
      throw new AppError("own_code", "That's your own connection code.", 400);
    }

    const { data: recipient, error: recipErr } = await service
      .from("profiles")
      .select("id, display_name, username")
      .eq("id", recipientId!)
      .maybeSingle();
    if (recipErr || !recipient) {
      throw new AppError("not_found", "Recipient profile not found", 404);
    }

    const { data: theyHavePerson } = await service.rpc("has_active_person", { p_user: recipientId });
    if (theyHavePerson) {
      throw new AppError(
        "target_has_person",
        "That person is already connected with someone else.",
        409,
      );
    }

    const { data: blocked } = await service.rpc("is_blocked", { a: me, b: recipientId });
    if (blocked) {
      throw new AppError("blocked", "Cannot send connection request", 403);
    }

    const { data: alreadyFriends } = await service.rpc("are_friends", {
      a: me,
      b: recipientId,
    });
    if (alreadyFriends) {
      throw new AppError("already_friends", "You're already connected with this person", 409);
    }

    const { data: pending } = await service.rpc("pending_friend_request_exists", {
      a: me,
      b: recipientId,
    });
    if (pending) {
      throw new AppError("pending_exists", "A pending connection request already exists", 409);
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
      throw new AppError("insert_failed", "Could not create connection request", 500);
    }

    const { data: meProfile } = await service
      .from("profiles")
      .select("display_name")
      .eq("id", me)
      .maybeSingle();
    const fromName = String(meProfile?.display_name ?? "Someone");
    if (await claimServerNotificationEvent(String(recipientId), null, `conn_req:${row.id}`)) {
      await sendPushToUser(String(recipientId), {
        title: "Connection Request",
        body: `${fromName} wants to connect with you.`,
        deepLink: "person",
        channel: "connections",
      });
    }

    return jsonResponse({
      request: row,
      recipient: {
        id: recipient.id,
        display_name: recipient.display_name,
        username: recipient.username,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
