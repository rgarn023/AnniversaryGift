import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

interface Body {
  query: string;
  limit?: number;
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
    // Derive caller from JWT (used implicitly by search_profiles via auth.uid()
    // when called with user client; here we filter self via service + exclude).
    const me = callerId(user);
    const body = (await req.json()) as Body;
    requireFields(body, ["query"]);

    const q = body.query.trim();
    if (q.length < 2) {
      throw new AppError("query_too_short", "Query must be at least 2 characters", 400);
    }

    const limit = Math.min(Math.max(body.limit ?? 20, 1), 50);
    const service = createServiceClient();

    // Public fields only — never email.
    const { data, error } = await service.rpc("search_profiles", {
      query: q,
      result_limit: limit,
    });

    if (error) {
      // Fallback if RPC auth.uid() is null under service role.
      console.warn("search_profiles rpc error, using fallback", error);
      const normalized = q.toLowerCase();
      const { data: rows, error: fbErr } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url")
        .neq("id", me)
        .or(
          `username.ilike.${normalized}%,friend_code.ilike.${q},display_name.ilike.%${q}%`,
        )
        .limit(limit);
      if (fbErr) throw new AppError("search_failed", "Search failed", 500);
      return jsonResponse({ profiles: rows ?? [] });
    }

    const profiles = (data ?? []).filter((p: { id: string }) => p.id !== me);
    return jsonResponse({ profiles });
  } catch (err) {
    return errorResponse(err);
  }
});
