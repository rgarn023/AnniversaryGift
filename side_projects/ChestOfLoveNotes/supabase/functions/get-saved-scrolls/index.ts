import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";
import { profileSafe, recipientScrollSafe } from "../_shared/scroll_meta.ts";

interface Filters {
  favorites_only?: boolean;
  password_protected_only?: boolean;
  sender_id?: string;
  title_query?: string;
  sort?: "newest" | "oldest";
}

/**
 * Saved Scrolls — recipient's saved, non-deleted copies.
 * Message bodies are NEVER returned; use open-scroll.
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

    let filters: Filters = {};
    if (req.method === "POST") {
      try {
        filters = (await req.json()) as Filters;
      } catch {
        filters = {};
      }
    } else {
      const url = new URL(req.url);
      filters = {
        favorites_only: url.searchParams.get("favorites_only") === "true",
        password_protected_only:
          url.searchParams.get("password_protected_only") === "true",
        sender_id: url.searchParams.get("sender_id") ?? undefined,
        title_query: url.searchParams.get("title") ?? undefined,
        sort: (url.searchParams.get("sort") as Filters["sort"]) ?? "newest",
      };
    }

    const service = createServiceClient();
    const ascending = filters.sort === "oldest";

    let query = service
      .from("scroll_recipient_states")
      .select(
        "scroll_id, recipient_id, is_read, is_saved, is_favorite, first_opened_at, last_opened_at, opened_count, deleted_at, created_at, updated_at",
      )
      .eq("recipient_id", me)
      .eq("is_saved", true)
      .is("deleted_at", null)
      .order("last_opened_at", { ascending, nullsFirst: false });

    if (filters.favorites_only) {
      query = query.eq("is_favorite", true);
    }

    const { data: states, error } = await query;
    if (error) {
      console.error(error);
      throw new AppError("fetch_failed", "Could not load saved scrolls", 500);
    }

    const scrollIds = (states ?? []).map((s) => s.scroll_id as string);
    if (scrollIds.length === 0) {
      return jsonResponse({ saved_scrolls: [], count: 0 });
    }

    let scrollQuery = service
      .from("scrolls")
      .select(
        "id, sender_id, recipient_id, title, unlock_at, has_password, created_at",
      )
      .in("id", scrollIds);

    if (filters.password_protected_only) {
      scrollQuery = scrollQuery.eq("has_password", true);
    }
    if (filters.sender_id) {
      scrollQuery = scrollQuery.eq("sender_id", filters.sender_id);
    }

    const { data: scrolls, error: scrollErr } = await scrollQuery;
    if (scrollErr) {
      console.error(scrollErr);
      throw new AppError("fetch_failed", "Could not load scroll metadata", 500);
    }

    const scrollById: Record<string, Record<string, unknown>> = {};
    for (const s of scrolls ?? []) {
      scrollById[s.id as string] = s as Record<string, unknown>;
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

    const titleQ = (filters.title_query ?? "").trim().toLowerCase();
    const now = Date.now();
    const saved_scrolls = (states ?? [])
      .map((st) => {
        const scroll = scrollById[st.scroll_id as string];
        if (!scroll) return null; // filtered out by sender/password
        if (
          titleQ &&
          !String(scroll.title ?? "").toLowerCase().includes(titleQ)
        ) {
          return null;
        }
        return recipientScrollSafe({
          scroll,
          state: st as Record<string, unknown>,
          sender: senders[String(scroll.sender_id)] ?? null,
          nowMs: now,
        });
      })
      .filter((x): x is NonNullable<typeof x> => x != null);

    return jsonResponse({
      saved_scrolls,
      count: saved_scrolls.length,
    });
  } catch (err) {
    return errorResponse(err);
  }
});
