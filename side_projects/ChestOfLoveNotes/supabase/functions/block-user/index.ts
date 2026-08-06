import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";

interface Body {
  blocked_id: string;
  action?: "block" | "unblock";
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    const { user } = await requireUser(req);
    const me = callerId(user);
    const body = (await req.json()) as Body;
    requireFields(body, ["blocked_id"]);

    const action = body.action ?? "block";
    if (!["block", "unblock"].includes(action)) {
      throw new AppError("invalid_action", "action must be block|unblock", 400);
    }
    if (body.blocked_id === me) {
      throw new AppError("invalid_request", "You cannot block yourself", 400);
    }

    const service = createServiceClient();

    const { data: target } = await service
      .from("profiles")
      .select("id")
      .eq("id", body.blocked_id)
      .maybeSingle();
    if (!target) throw new AppError("not_found", "User not found", 404);

    if (action === "unblock") {
      const { error } = await service
        .from("blocks")
        .delete()
        .eq("blocker_id", me)
        .eq("blocked_id", body.blocked_id);
      if (error) throw new AppError("unblock_failed", "Could not unblock user", 500);
      return jsonResponse({ blocked_id: body.blocked_id, status: "unblocked" });
    }

    const { error: blockErr } = await service.from("blocks").upsert(
      { blocker_id: me, blocked_id: body.blocked_id },
      { onConflict: "blocker_id,blocked_id", ignoreDuplicates: true },
    );
    if (blockErr) {
      console.error(blockErr);
      throw new AppError("block_failed", "Could not block user", 500);
    }

    // Remove friendship if present (normalized pair).
    const userOne = me < body.blocked_id ? me : body.blocked_id;
    const userTwo = me < body.blocked_id ? body.blocked_id : me;
    await service
      .from("friendships")
      .delete()
      .eq("user_one_id", userOne)
      .eq("user_two_id", userTwo);

    // Cancel any pending requests either direction.
    await service
      .from("friend_requests")
      .update({ status: "cancelled", responded_at: new Date().toISOString() })
      .eq("status", "pending")
      .or(
        `and(sender_id.eq.${me},recipient_id.eq.${body.blocked_id}),and(sender_id.eq.${body.blocked_id},recipient_id.eq.${me})`,
      );

    return jsonResponse({ blocked_id: body.blocked_id, status: "blocked" });
  } catch (err) {
    return errorResponse(err);
  }
});
