import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient, createUserClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

interface Body {
  scroll_id: string;
}

/**
 * Permanently deletes the sender's Sent Scrolls entry only (per-user).
 * Does not recall the message or remove the recipient copy.
 * Physical erasure only when both parties deleted.
 */
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

    const service = createServiceClient();
    const userClient = createUserClient(authHeader);

    const { data: scroll } = await service
      .from("scrolls")
      .select("id, sender_id")
      .eq("id", body.scroll_id)
      .maybeSingle();

    if (!scroll) {
      throw new AppError("not_found", "Scroll not found", 404);
    }
    if (scroll.sender_id !== me) {
      throw new AppError(
        "forbidden",
        "Only the sender can hide this sent entry",
        403,
      );
    }

    const { data: updated, error } = await userClient.rpc(
      "soft_delete_sender_scroll",
      { p_scroll_id: body.scroll_id },
    );

    if (error || !updated) {
      console.error(error);
      throw new AppError("delete_failed", "Could not soft-delete sent scroll", 400);
    }

    const row = Array.isArray(updated) ? updated[0] : updated;
    return jsonResponse({
      ok: true,
      soft_deleted: true,
      permanently_deleted_for_user: true,
      recalled: false,
      physical_erasure: false,
      scroll_id: body.scroll_id,
      sender_state: {
        scroll_id: row.scroll_id,
        sender_id: row.sender_id,
        deleted_at: row.deleted_at,
        hidden_at: row.hidden_at ?? null,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
