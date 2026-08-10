import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

/** Returns My Person (0 or 1) + pending connection requests. */
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
      .or(`user_one_id.eq.${me},user_two_id.eq.${me}`)
      .limit(1);

    if (error) {
      console.error(error);
      throw new AppError("fetch_failed", "Could not load My Person", 500);
    }

    let person: Record<string, unknown> | null = null;
    let connectedAt: string | null = null;
    if (friendships && friendships.length > 0) {
      const f = friendships[0];
      connectedAt = f.created_at as string;
      const personId = f.user_one_id === me ? f.user_two_id : f.user_one_id;
      const { data: profile, error: pErr } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url, public_connection_token")
        .eq("id", personId)
        .maybeSingle();
      if (pErr) throw new AppError("fetch_failed", "Could not load Person profile", 500);
      if (profile) {
        person = {
          id: profile.id,
          username: profile.username,
          display_name: profile.display_name,
          friend_code: profile.friend_code,
          avatar_url: profile.avatar_url,
          connected_at: connectedAt,
          // Never return their public_connection_token to the other party.
        };
      }
    }

    const { data: meProfile } = await service
      .from("profiles")
      .select("id, username, display_name, friend_code, public_connection_token")
      .eq("id", me)
      .maybeSingle();

    const { data: incoming } = await service
      .from("friend_requests")
      .select("id, sender_id, recipient_id, status, message, created_at")
      .eq("recipient_id", me)
      .eq("status", "pending")
      .order("created_at", { ascending: false });

    const incomingIds = (incoming ?? []).map((r) => r.sender_id as string);
    let senderMap: Record<string, Record<string, unknown>> = {};
    if (incomingIds.length > 0) {
      const { data: senders } = await service
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", incomingIds);
      for (const s of senders ?? []) {
        senderMap[String(s.id)] = s;
      }
    }
    const incoming_requests = (incoming ?? []).map((r) => ({
      ...r,
      sender: senderMap[String(r.sender_id)] ?? null,
    }));

    const { data: outgoing } = await service
      .from("friend_requests")
      .select("id, sender_id, recipient_id, status, message, created_at")
      .eq("sender_id", me)
      .eq("status", "pending")
      .order("created_at", { ascending: false });

    // Compat: "friends" array is 0 or 1 person for older clients.
    const friends = person ? [person] : [];

    return jsonResponse({
      person,
      friends,
      connected_at: connectedAt,
      me: meProfile
        ? {
          id: meProfile.id,
          username: meProfile.username,
          display_name: meProfile.display_name,
          friend_code: meProfile.friend_code,
          public_connection_token: meProfile.public_connection_token,
          connection_deep_link: `chestoflovenotes://connect/${meProfile.public_connection_token}`,
        }
        : null,
      incoming_requests,
      outgoing_requests: outgoing ?? [],
    });
  } catch (err) {
    return errorResponse(err);
  }
});
