import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse } from "../_shared/errors.ts";
import { claimServerNotificationEvent, sendPushToUser } from "../_shared/push.ts";

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    if (req.method !== "POST") throw new AppError("method_not_allowed", "POST required", 405);
    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const service = createServiceClient();

    const { data: friendships, error } = await service
      .from("friendships")
      .select("id, user_one_id, user_two_id")
      .or(`user_one_id.eq.${me},user_two_id.eq.${me}`);
    if (error) throw new AppError("fetch_failed", "Could not load connection.", 500);
    if (!friendships || friendships.length === 0) {
      throw new AppError("not_connected", "You are not connected with anyone.", 404);
    }
    const f = friendships[0];
    const otherId = f.user_one_id === me ? f.user_two_id : f.user_one_id;

    const { data: meProfile } = await service
      .from("profiles")
      .select("display_name")
      .eq("id", me)
      .maybeSingle();

    const { error: delErr } = await service.from("friendships").delete().eq("id", f.id);
    if (delErr) {
      console.error(delErr);
      throw new AppError("disconnect_failed", "Could not disconnect.", 500);
    }

    // Optional notify other party (privacy-safe).
    const name = String(meProfile?.display_name ?? "Your Person");
    if (await claimServerNotificationEvent(String(otherId), null, `disconnect:${f.id}`)) {
      await sendPushToUser(String(otherId), {
        title: "Connection ended",
        body: `You're no longer connected with ${name}.`,
        deepLink: "person",
        channel: "connections",
      });
    }

    return jsonResponse({ ok: true, disconnected_from: otherId });
  } catch (err) {
    return errorResponse(err);
  }
});
