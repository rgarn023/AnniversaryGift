import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

/**
 * Returns short-lived signed download URLs for attachments on a scroll
 * the caller is authorized to view (sender or recipient).
 */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }
    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const body = await req.json() as { scroll_id?: string };
    requireFields(body, ["scroll_id"]);
    const service = createServiceClient();
    const { data: scroll, error: scrollErr } = await service
      .from("scrolls")
      .select("id, sender_id, recipient_id")
      .eq("id", body.scroll_id)
      .maybeSingle();
    if (scrollErr || !scroll) {
      throw new AppError("not_found", "Scroll not found", 404);
    }
    if (scroll.sender_id !== me && scroll.recipient_id !== me) {
      throw new AppError("forbidden", "Not allowed to view these attachments", 403);
    }
    const { data: rows, error } = await service
      .from("scroll_attachments")
      .select("id, storage_path, mime_type, width, height, byte_size, sort_order")
      .eq("scroll_id", body.scroll_id)
      .order("sort_order", { ascending: true });
    if (error) {
      console.error(error);
      throw new AppError("fetch_failed", "Could not load attachments", 500);
    }
    const attachments: Array<Record<string, unknown>> = [];
    for (const row of rows ?? []) {
      const { data: signed, error: signErr } = await service.storage
        .from("scroll-attachments")
        .createSignedUrl(String(row.storage_path), 300);
      if (signErr || !signed?.signedUrl) {
        console.error(signErr);
        continue;
      }
      attachments.push({
        id: row.id,
        mime_type: row.mime_type,
        width: row.width,
        height: row.height,
        byte_size: row.byte_size,
        sort_order: row.sort_order,
        signed_url: signed.signedUrl,
      });
    }
    return jsonResponse({ attachments });
  } catch (err) {
    return errorResponse(err);
  }
});
