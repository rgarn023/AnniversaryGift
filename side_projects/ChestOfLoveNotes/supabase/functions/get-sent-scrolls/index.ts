import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

/**
 * Lists scrolls the caller has sent (metadata only — never message body).
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

    const { data: scrolls, error } = await service
      .from("scrolls")
      .select(
        "id, sender_id, recipient_id, title, unlock_at, has_password, is_opened, opened_at, created_at",
      )
      .eq("sender_id", me)
      .is("deleted_at", null)
      .order("created_at", { ascending: false });

    if (error) {
      console.error(error);
      throw new AppError("fetch_failed", "Could not load sent scrolls", 500);
    }

    const recipientIds = [
      ...new Set((scrolls ?? []).map((s) => s.recipient_id as string)),
    ];
    let recipients: Record<string, unknown> = {};
    if (recipientIds.length > 0) {
      const { data: profiles } = await service
        .from("profiles")
        .select("id, username, display_name, friend_code, avatar_url")
        .in("id", recipientIds);
      for (const p of profiles ?? []) {
        recipients[p.id as string] = p;
      }
    }

    const items = (scrolls ?? []).map((s) => ({
      ...s,
      recipient: recipients[s.recipient_id as string] ?? null,
    }));

    return jsonResponse({ sent_scrolls: items });
  } catch (err) {
    return errorResponse(err);
  }
});
