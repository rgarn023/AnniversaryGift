import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

/**
 * Canonical active My Person = presence of a friendships row involving me.
 *
 * CRITICAL: Do NOT reconcile / recreate friendships from historical
 * friend_requests.status='accepted'. That path auto-reconnected Mandy after
 * disconnect. Accept already inserts the friendship once; reconnect requires
 * a NEW pending request + NEW accept (which clears my_person_pair_ends).
 */
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

    // Intentionally NO reconcileAcceptedPairing / no friendship INSERT here.
    const reconciliation_last_result = "no_change";

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
    let pairEnded = false;
    let historicalAcceptedPresent = false;

    if (friendships && friendships.length > 0) {
      const f = friendships[0];
      pairingId = f.id as string;
      connectedAt = f.created_at as string;
      personId = (f.user_one_id === me ? f.user_two_id : f.user_one_id) as string;

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
    } else {
      // Diagnostics only — never recreate from these.
      const { data: ends, error: endsErr } = await service
        .from("my_person_pair_ends")
        .select("user_one_id, user_two_id")
        .or(`user_one_id.eq.${me},user_two_id.eq.${me}`)
        .limit(1);
      if (endsErr) {
        // Table missing until migration applied — treat as no tombstone for diagnostics.
        pairEnded = false;
      } else {
        pairEnded = !!(ends && ends.length > 0);
      }

      const { data: acceptedHist } = await service
        .from("friend_requests")
        .select("id")
        .eq("status", "accepted")
        .or(`sender_id.eq.${me},recipient_id.eq.${me}`)
        .limit(1);
      historicalAcceptedPresent = !!(acceptedHist && acceptedHist.length > 0);
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

    const friends = person ? [person] : [];
    const relationship_status = person ? "active" : (pairEnded ? "disconnected" : "none");

    return jsonResponse({
      person,
      friends,
      connected_at: connectedAt,
      pairing_id: pairingId,
      active_pairing: !!person,
      relationship_status,
      pair_end_tombstone: pairEnded,
      historical_accepted_request: historicalAcceptedPresent,
      legacy_migration_eligible: false,
      reconciliation_last_result,
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
