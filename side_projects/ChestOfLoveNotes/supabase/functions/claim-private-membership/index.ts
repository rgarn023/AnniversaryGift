import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    const { user } = await requireUser(req);
    const userId = callerId(user);
    const email = (user.email ?? "").trim().toLowerCase();
    if (!email) {
      throw new AppError("forbidden", "Verified email required for private access", 403);
    }

    const service = createServiceClient();
    const { data, error } = await service.rpc("claim_private_app_membership", {
      p_user_id: userId,
      p_email: email,
    });

    if (error) {
      const msg = error.message ?? "Membership claim failed";
      if (msg.includes("not on the private allowlist")) {
        throw new AppError(
          "forbidden",
          "This account is not invited to the private app",
          403,
        );
      }
      throw new AppError("claim_failed", "Unable to claim private membership", 400);
    }

    return jsonResponse({
      ok: true,
      member: {
        user_id: data.user_id,
        role: data.role,
        status: data.status,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
