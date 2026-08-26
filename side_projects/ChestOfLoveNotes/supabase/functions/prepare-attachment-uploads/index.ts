import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

const MAX_ATTACHMENTS = 5;
const ALLOWED = new Set(["image/jpeg", "image/png", "image/webp"]);

interface Item {
  mime_type?: string;
  byte_size?: number;
}

/**
 * Issues private signed upload URLs for pending scroll photo attachments.
 * Paths: pending/{user_id}/{session_id}/{index}.ext
 * Client uploads, then send-scroll registers them against the new scroll.
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
    const body = await req.json() as { items?: Item[] };
    const items = Array.isArray(body.items) ? body.items : [];
    if (items.length < 1 || items.length > MAX_ATTACHMENTS) {
      throw new AppError(
        "invalid_attachments",
        `Choose 1–${MAX_ATTACHMENTS} photos.`,
        400,
      );
    }
    const service = createServiceClient();
    const sessionId = crypto.randomUUID();
    const uploads: Array<Record<string, unknown>> = [];
    for (let i = 0; i < items.length; i++) {
      const mime = String(items[i]?.mime_type ?? "image/jpeg");
      if (!ALLOWED.has(mime)) {
        throw new AppError("invalid_attachments", "Photos must be JPEG, PNG, or WebP.", 400);
      }
      const size = Number(items[i]?.byte_size ?? 0);
      if (!Number.isFinite(size) || size <= 0 || size > 5_242_880) {
        throw new AppError("invalid_attachments", "Each photo must be under 5 MB after compression.", 400);
      }
      const ext = mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg";
      const path = `pending/${me}/${sessionId}/${i}.${ext}`;
      const { data, error } = await service.storage
        .from("scroll-attachments")
        .createSignedUploadUrl(path);
      if (error || !data) {
        console.error(error);
        throw new AppError("upload_prepare_failed", "Could not prepare photo upload.", 500);
      }
      uploads.push({
        path,
        mime_type: mime,
        token: data.token,
        signed_url: data.signedUrl,
        sort_order: i,
      });
    }
    return jsonResponse({
      session_id: sessionId,
      uploads,
      max_attachments: MAX_ATTACHMENTS,
    });
  } catch (err) {
    return errorResponse(err);
  }
});
