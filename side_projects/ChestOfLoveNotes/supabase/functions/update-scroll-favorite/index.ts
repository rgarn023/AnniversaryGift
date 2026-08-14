import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient, createUserClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

interface Body {
  scroll_id: string;
  is_favorite: boolean;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    const { user, authHeader } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const body = (await req.json()) as Body;
    requireFields(body, ["scroll_id"]);
    if (typeof body.is_favorite !== "boolean") {
      throw new AppError("missing_field", "is_favorite must be a boolean", 400);
    }

    const service = createServiceClient();
    const userClient = createUserClient(authHeader);

    const { data: scroll } = await service
      .from("scrolls")
      .select("id, recipient_id")
      .eq("id", body.scroll_id)
      .maybeSingle();

    if (!scroll) {
      throw new AppError("not_found", "Scroll not found", 404);
    }
    if (scroll.recipient_id !== me) {
      throw new AppError(
        "forbidden",
        "Only the recipient can favorite this scroll",
        403,
      );
    }

    const { data: state } = await service
      .from("scroll_recipient_states")
      .select("deleted_at")
      .eq("scroll_id", body.scroll_id)
      .eq("recipient_id", me)
      .maybeSingle();

    if (state?.deleted_at) {
      throw new AppError("deleted", "This scroll is no longer available", 410);
    }

    // Must run as the user so auth.uid() matches the recipient.
    const { data: updated, error } = await userClient.rpc(
      "set_recipient_scroll_favorite",
      {
        p_scroll_id: body.scroll_id,
        p_favorite: body.is_favorite,
      },
    );

    if (error || !updated) {
      console.error(error);
      throw new AppError("update_failed", "Could not update favorite state", 400);
    }

    const row = Array.isArray(updated) ? updated[0] : updated;
    return jsonResponse({
      ok: true,
      recipient_state: {
        scroll_id: row.scroll_id,
        recipient_id: row.recipient_id,
        is_read: row.is_read,
        is_saved: row.is_saved,
        is_favorite: row.is_favorite,
        first_opened_at: row.first_opened_at,
        last_opened_at: row.last_opened_at,
        opened_count: row.opened_count,
        deleted_at: row.deleted_at,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
