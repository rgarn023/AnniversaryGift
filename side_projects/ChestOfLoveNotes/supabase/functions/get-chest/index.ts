import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

/**
 * Returns the caller's chest: received scrolls (metadata only).
 * Never includes ciphertext / password hashes.
 */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST" && req.method !== "GET") {
      throw new AppError("method_not_allowed", "GET or POST required", 405);
    }

    const { user } = await requireUser(req);
    const me = callerId(user);
    const service = createServiceClient();

    const { data: scrolls, error } = await service
      .from("scrolls")
      .select(
        "id, sender_id, recipient_id, title, unlock_at, has_password, is_opened, opened_at, created_at",
      )
      .eq("recipient_id", me)
      .is("deleted_at", null)
      .order("unlock_at", { ascending: false });

    if (error) {
      console.error(error);
      throw new AppError("fetch_failed", "Could not load chest", 500);
    }

    const senderIds = [...new Set((scrolls ?? []).map((s) => s.sender_id as string))];
    let senders: Record<string, unknown> = {};
    if (senderIds.length > 0) {
      const { data: profiles } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url")
        .in("id", senderIds);
      for (const p of profiles ?? []) {
        senders[p.id as string] = p;
      }
    }

    const now = Date.now();
    const items = (scrolls ?? []).map((s) => ({
      ...s,
      is_unlockable: new Date(s.unlock_at as string).getTime() <= now,
      sender: senders[s.sender_id as string] ?? null,
    }));

    return jsonResponse({
      chest: {
        user_id: me,
        count: items.length,
        unopened: items.filter((i) => !i.is_opened).length,
        scrolls: items,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
