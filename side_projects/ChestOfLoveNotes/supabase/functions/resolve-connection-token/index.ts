import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

interface Body {
  token?: string;
  deep_link?: string;
}

function extractToken(raw: string): string {
  let t = raw.trim();
  // chestoflovenotes://connect/<token> or https://.../connect/<token>
  const m = t.match(/(?:chestoflovenotes:\/\/connect\/|\/connect\/)([A-Za-z0-9_-]+)/i);
  if (m) t = m[1];
  t = t.replace(/^connect\//i, "");
  return t.trim().toLowerCase();
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
    const raw = (body.token ?? body.deep_link ?? "").trim();
    requireFields({ token: raw }, ["token"]);
    const token = extractToken(raw);
    if (token.length < 16) {
      throw new AppError("invalid_code", "This isn't a valid Chest of Love Notes connection code.", 400);
    }

    const service = createServiceClient();
    const { data: rows, error } = await service.rpc("resolve_connection_token", { p_token: token });
    if (error) {
      console.error(error);
      throw new AppError("lookup_failed", "Could not resolve connection code.", 500);
    }
    const row = Array.isArray(rows) ? rows[0] : rows;
    if (!row || !row.id) {
      throw new AppError("invalid_code", "This isn't a valid Chest of Love Notes connection code.", 404);
    }
    if (String(row.id) === me) {
      throw new AppError("own_code", "That's your own connection code.", 400);
    }

    // Also allow lookup by friend_code / username via same endpoint when token-shaped fails —
    // callers that pass CHEST- or username use send-connection-request instead.

    return jsonResponse({
      profile: {
        id: row.id,
        username: row.username ?? "",
        display_name: row.display_name ?? "",
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
