import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST" && req.method !== "GET") {
      throw new AppError("method_not_allowed", "GET or POST required", 405);
    }

    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const service = createServiceClient();

    const { data: friendships, error } = await service
      .from("friendships")
      .select("id, user_one_id, user_two_id, created_at")
      .or(`user_one_id.eq.${me},user_two_id.eq.${me}`);

    if (error) {
      console.error(error);
      throw new AppError("fetch_failed", "Could not load friendships", 500);
    }

    const friendIds = (friendships ?? []).map((f) =>
      f.user_one_id === me ? (f.user_two_id as string) : (f.user_one_id as string),
    );

    let friends: unknown[] = [];
    if (friendIds.length > 0) {
      const { data: profiles, error: pErr } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url")
        .in("id", friendIds);
      if (pErr) throw new AppError("fetch_failed", "Could not load friend profiles", 500);
      friends = profiles ?? [];
    }

    const { data: incoming } = await service
      .from("friend_requests")
      .select("id, sender_id, recipient_id, status, message, created_at")
      .eq("recipient_id", me)
      .eq("status", "pending")
      .order("created_at", { ascending: false });

    const { data: outgoing } = await service
      .from("friend_requests")
      .select("id, sender_id, recipient_id, status, message, created_at")
      .eq("sender_id", me)
      .eq("status", "pending")
      .order("created_at", { ascending: false });

    return jsonResponse({
      friends,
      incoming_requests: incoming ?? [],
      outgoing_requests: outgoing ?? [],
    });
  } catch (err) {
    return errorResponse(err);
  }
});
