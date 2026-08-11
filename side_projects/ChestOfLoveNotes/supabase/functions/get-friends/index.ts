import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

/** Ensure an accepted friend_request has a corresponding mutual friendship row. */
async function reconcileAcceptedPairing(
  service: ReturnType<typeof createServiceClient>,
  me: string,
): Promise<void> {
  // Legacy / missed-accept repair: accepted request exists but friendships row missing.
  const { data: accepted } = await service
    .from("friend_requests")
    .select("id, sender_id, recipient_id, status, responded_at, created_at")
    .eq("status", "accepted")
    .or(`sender_id.eq.${me},recipient_id.eq.${me}`)
    .order("responded_at", { ascending: true, nullsFirst: false })
    .limit(20);

  if (!accepted || accepted.length === 0) return;

  const { data: existing } = await service
    .from("friendships")
    .select("id, user_one_id, user_two_id")
    .or(`user_one_id.eq.${me},user_two_id.eq.${me}`)
    .limit(1);

  if (existing && existing.length > 0) return;

  // Prefer the earliest accepted request involving me; normalize to one mutual row.
  for (const fr of accepted) {
    const a = String(fr.sender_id);
    const b = String(fr.recipient_id);
    if (!a || !b || a === b) continue;
    const userOne = a < b ? a : b;
    const userTwo = a < b ? b : a;

    // Skip if either party already has a different active person.
    const { data: aHas } = await service.rpc("has_active_person", { p_user: a });
    const { data: bHas } = await service.rpc("has_active_person", { p_user: b });
    if (aHas || bHas) continue;

    const { error: insErr } = await service.from("friendships").insert({
      user_one_id: userOne,
      user_two_id: userTwo,
    });
    if (!insErr) {
      console.log("reconciled accepted friend_request into friendship", fr.id);
      return;
    }
    // Unique / already_has_person → stop; another concurrent path created it.
    console.warn("reconcile insert skipped", insErr.message ?? insErr);
    return;
  }
}

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

    await reconcileAcceptedPairing(service, me);

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
    let pairingId: string | null = null;
    let personId: string | null = null;
    if (friendships && friendships.length > 0) {
      const f = friendships[0];
      pairingId = f.id as string;
      connectedAt = f.created_at as string;
      personId = (f.user_one_id === me ? f.user_two_id : f.user_one_id) as string;

      // Profile hydration is separate from pairing existence — never drop a valid pair.
      const { data: profile, error: pErr } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url")
        .eq("id", personId)
        .maybeSingle();

      if (pErr) {
        console.warn("person profile lookup failed; returning pairing with fallback", pErr);
      }

      if (profile) {
        person = {
          id: profile.id,
          username: profile.username,
          display_name: profile.display_name,
          friend_code: profile.friend_code,
          avatar_url: profile.avatar_url,
          connected_at: connectedAt,
          pairing_id: pairingId,
          profile_pending: false,
        };
      } else {
        // Pairing exists; profile temporarily unavailable — keep Person, not empty state.
        person = {
          id: personId,
          username: "",
          display_name: "My Person",
          friend_code: "",
          avatar_url: null,
          connected_at: connectedAt,
          pairing_id: pairingId,
          profile_pending: true,
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
      pairing_id: pairingId,
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
