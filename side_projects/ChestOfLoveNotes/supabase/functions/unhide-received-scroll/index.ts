import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient, createUserClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

interface Body {
  scroll_id: string;
}

/** Recipient Unhide — restores to normal chest lists. */
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
      .select("id, recipient_id")
      .eq("id", body.scroll_id)
      .maybeSingle();

    if (!scroll) {
      throw new AppError("not_found", "Scroll not found", 404);
    }
    if (scroll.recipient_id !== me) {
      throw new AppError("forbidden", "Only the recipient can unhide their copy", 403);
    }

    const { data: updated, error } = await userClient.rpc("unhide_recipient_scroll", {
      p_scroll_id: body.scroll_id,
    });

    if (error || !updated) {
      console.error(error);
      throw new AppError("unhide_failed", "Could not unhide received scroll", 400);
    }

    const row = Array.isArray(updated) ? updated[0] : updated;
    return jsonResponse({
      ok: true,
      hidden: false,
      scroll_id: body.scroll_id,
      recipient_state: {
        scroll_id: row.scroll_id,
        recipient_id: row.recipient_id,
        hidden_at: row.hidden_at,
        deleted_at: row.deleted_at ?? null,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
