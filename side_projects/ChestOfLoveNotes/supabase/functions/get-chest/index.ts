import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";
import { profileSafe, recipientScrollSafe } from "../_shared/scroll_meta.ts";

/**
 * Current Scrolls (chest): locked + unlocked unread + newly received + friend requests.
 * Excludes recipient soft-deleted copies and saved/opened items (those live in Saved).
 * Never returns message bodies or scroll_contents fields.
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

    // Current = not deleted by recipient AND not yet saved (opened moves to Saved).
    const { data: states, error } = await service
      .from("scroll_recipient_states")
      .select(
        "scroll_id, recipient_id, is_read, is_saved, is_favorite, first_opened_at, last_opened_at, opened_count, deleted_at",
      )
      .eq("recipient_id", me)
      .is("deleted_at", null)
      .eq("is_saved", false)
      .order("created_at", { ascending: false });

    if (error) {
      console.error(error);
      throw new AppError("fetch_failed", "Could not load chest", 500);
    }

    const scrollIds = (states ?? []).map((s) => s.scroll_id as string);
    let scrollById: Record<string, Record<string, unknown>> = {};
    if (scrollIds.length > 0) {
      const { data: scrolls, error: scrollErr } = await service
        .from("scrolls")
        .select(
          "id, sender_id, recipient_id, title, unlock_at, has_password, created_at",
        )
        .in("id", scrollIds);
      if (scrollErr) {
        console.error(scrollErr);
        throw new AppError("fetch_failed", "Could not load scroll metadata", 500);
      }
      for (const s of scrolls ?? []) {
        scrollById[s.id as string] = s as Record<string, unknown>;
      }
    }

    const senderIds = [
      ...new Set(
        Object.values(scrollById).map((s) => String(s.sender_id ?? "")).filter(Boolean),
      ),
    ];
    const senders: Record<string, ReturnType<typeof profileSafe>> = {};
    if (senderIds.length > 0) {
      const { data: profiles } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url")
        .in("id", senderIds);
      for (const p of profiles ?? []) {
        senders[p.id as string] = profileSafe(p as Record<string, unknown>);
      }
    }

    const now = Date.now();
    const scrolls = (states ?? [])
      .map((st) => {
        const scroll = scrollById[st.scroll_id as string];
        if (!scroll) return null;
        return recipientScrollSafe({
          scroll,
          state: st as Record<string, unknown>,
          sender: senders[String(scroll.sender_id)] ?? null,
          nowMs: now,
        });
      })
      .filter((x): x is NonNullable<typeof x> => x != null);

    // Friend requests (incoming pending) for Current Scrolls / chest UI.
    const { data: requests } = await service
      .from("friend_requests")
      .select("id, sender_id, recipient_id, status, created_at, message")
      .eq("recipient_id", me)
      .eq("status", "pending")
      .order("created_at", { ascending: false });

    const reqSenderIds = [
      ...new Set((requests ?? []).map((r) => r.sender_id as string)),
    ];
    const reqSenders: Record<string, ReturnType<typeof profileSafe>> = {};
    if (reqSenderIds.length > 0) {
      const { data: profiles } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url")
        .in("id", reqSenderIds);
      for (const p of profiles ?? []) {
        reqSenders[p.id as string] = profileSafe(p as Record<string, unknown>);
      }
    }

    const friend_requests = (requests ?? []).map((r) => ({
      id: r.id,
      kind: "friend_request",
      sender_id: r.sender_id,
      recipient_id: r.recipient_id,
      status: r.status,
      created_at: r.created_at,
      sender: reqSenders[r.sender_id as string] ?? null,
    }));

    return jsonResponse({
      chest: {
        user_id: me,
        count: scrolls.length,
        unread: scrolls.filter((s) => !s.is_read).length,
        locked: scrolls.filter((s) => !s.is_unlockable).length,
        // Compatibility
        unopened: scrolls.filter((s) => !s.is_read).length,
        scrolls,
        friend_requests,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
