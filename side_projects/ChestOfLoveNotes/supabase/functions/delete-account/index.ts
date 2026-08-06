import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

interface Body {
  confirm?: boolean;
}

/**
 * Hard-delete the caller's auth user. Cascades remove profile, friendships,
 * requests, blocks, scrolls, and scroll_contents via FK ON DELETE CASCADE.
 */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    const { user } = await requireUser(req);
    const me = callerId(user);
    const body = (await req.json().catch(() => ({}))) as Body;

    if (body.confirm !== true) {
      throw new AppError(
        "confirmation_required",
        "Pass { confirm: true } to permanently delete your account",
        400,
      );
    }

    const service = createServiceClient();

    // Soft-delete scrolls where user is sender (extra safety before auth delete).
    await service
      .from("scrolls")
      .update({ deleted_at: new Date().toISOString() })
      .or(`sender_id.eq.${me},recipient_id.eq.${me}`);

    const { error } = await service.auth.admin.deleteUser(me);
    if (error) {
      console.error(error);
      throw new AppError("delete_failed", "Could not delete account", 500);
    }

    return jsonResponse({ deleted: true, user_id: me });
  } catch (err) {
    return errorResponse(err);
  }
});
