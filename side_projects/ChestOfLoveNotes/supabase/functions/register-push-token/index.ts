import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

interface Body {
  token: string;
  platform?: string;
  device_label?: string;
  active?: boolean;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    if (req.method !== "POST") throw new AppError("method_not_allowed", "POST required", 405);
    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const body = (await req.json()) as Body;
    requireFields(body, ["token"]);
    const token = String(body.token ?? "").trim();
    if (token.length < 8 || token.length > 512) {
      throw new AppError("invalid_token", "Invalid push token.", 400);
    }
    const platform = (body.platform ?? "android").toLowerCase();
    if (!["android", "ios", "web"].includes(platform)) {
      throw new AppError("invalid_platform", "Unsupported platform.", 400);
    }
    const active = body.active !== false;
    const service = createServiceClient();

    // Upsert by token; bind to authenticated user.
    const { data: existing } = await service
      .from("device_push_tokens")
      .select("id, user_id")
      .eq("token", token)
      .maybeSingle();

    if (existing) {
      const { error } = await service
        .from("device_push_tokens")
        .update({
          user_id: me,
          platform,
          device_label: String(body.device_label ?? "").slice(0, 80),
          active,
        })
        .eq("id", existing.id);
      if (error) throw new AppError("update_failed", "Could not update push token.", 500);
    } else if (active) {
      const { error } = await service.from("device_push_tokens").insert({
        user_id: me,
        token,
        platform,
        device_label: String(body.device_label ?? "").slice(0, 80),
        active: true,
      });
      if (error) throw new AppError("insert_failed", "Could not register push token.", 500);
    }

    return jsonResponse({ ok: true });
  } catch (err) {
    return errorResponse(err);
  }
});
