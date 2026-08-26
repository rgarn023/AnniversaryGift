import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";
import { profileSafe, sentScrollSafe } from "../_shared/scroll_meta.ts";

/**
 * Sent Scrolls for the authenticated sender.
 * Excludes sender-state soft-deleted rows. Never returns contents/passwords.
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

    let view = "current";
    if (req.method === "POST") {
      try {
        const body = (await req.json()) as { view?: string };
        if (body?.view === "hidden") view = "hidden";
      } catch {
        view = "current";
      }
    } else {
      const url = new URL(req.url);
      if (url.searchParams.get("view") === "hidden") view = "hidden";
    }

    // Permanent deletes excluded always. Hidden view returns only hidden_at rows.
    let q = service
      .from("scroll_sender_states")
      .select("scroll_id, sender_id, deleted_at, hidden_at, created_at")
      .eq("sender_id", me)
      .is("deleted_at", null);
    if (view === "hidden") {
      q = q.not("hidden_at", "is", null);
    } else {
      q = q.is("hidden_at", null);
    }
    const { data: states, error } = await q.order("created_at", { ascending: false });

    if (error) {
      console.error(error);
      throw new AppError("fetch_failed", "Could not load sent scrolls", 500);
    }

    const scrollIds = (states ?? []).map((s) => s.scroll_id as string);
    if (scrollIds.length === 0) {
      return jsonResponse({ sent_scrolls: [] });
    }

    const { data: scrolls, error: scrollErr } = await service
      .from("scrolls")
      .select(
        "id, sender_id, recipient_id, title, unlock_at, has_password, has_location_lock, location_name, location_address, location_lat, location_lng, location_radius_m, created_at",
      )
      .in("id", scrollIds);

    if (scrollErr) {
      console.error(scrollErr);
      throw new AppError("fetch_failed", "Could not load scroll metadata", 500);
    }

    const scrollById: Record<string, Record<string, unknown>> = {};
    for (const s of scrolls ?? []) {
      scrollById[s.id as string] = s as Record<string, unknown>;
    }

    const { data: recipientStates } = await service
      .from("scroll_recipient_states")
      .select(
        "scroll_id, recipient_id, is_read, first_opened_at, last_opened_at, opened_count",
      )
      .in("scroll_id", scrollIds);

    const recipientStateByScroll: Record<string, Record<string, unknown>> = {};
    for (const rs of recipientStates ?? []) {
      recipientStateByScroll[rs.scroll_id as string] = rs as Record<string, unknown>;
    }

    const recipientIds = [
      ...new Set(
        Object.values(scrollById).map((s) => String(s.recipient_id ?? "")).filter(Boolean),
      ),
    ];
    const recipients: Record<string, ReturnType<typeof profileSafe>> = {};
    if (recipientIds.length > 0) {
      const { data: profiles } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url")
        .in("id", recipientIds);
      for (const p of profiles ?? []) {
        recipients[p.id as string] = profileSafe(p as Record<string, unknown>);
      }
    }

    const stateByScroll: Record<string, Record<string, unknown>> = {};
    for (const st of states ?? []) {
      stateByScroll[st.scroll_id as string] = st as Record<string, unknown>;
    }

    const items = scrollIds
      .map((id) => {
        const scroll = scrollById[id];
        const senderState = stateByScroll[id];
        if (!scroll || !senderState) return null;
        return sentScrollSafe({
          scroll,
          senderState,
          recipientState: recipientStateByScroll[id] ?? null,
          recipient: recipients[String(scroll.recipient_id)] ?? null,
        });
      })
      .filter((x): x is NonNullable<typeof x> => x != null);

    return jsonResponse({ sent_scrolls: items });
  } catch (err) {
    return errorResponse(err);
  }
});
