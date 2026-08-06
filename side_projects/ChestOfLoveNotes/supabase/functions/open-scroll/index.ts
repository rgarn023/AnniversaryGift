import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient, createUserClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";
import { decryptMessage, verifyPassword } from "../_shared/crypto.ts";
import { assertNotRateLimited, recordAttempt } from "../_shared/rate_limit.ts";

interface Body {
  scroll_id: string;
  password?: string;
  /** Godot client compatibility alias */
  magic_password?: string;
}

/**
 * Open-scroll authorization order:
 * 1. Authenticate
 * 2. Private-app membership
 * 3. Caller is recipient
 * 4. Recipient copy not soft-deleted
 * 5. Block rules
 * 6. Server time vs unlock_at
 * 7. Password-attempt limits
 * 8. Magic password if required
 * 9. Decrypt
 * 10. mark_recipient_scroll_opened (atomic read+saved+counters)
 * 11. Return decrypted message
 */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    // 1–2. Auth + private membership
    const { user, authHeader } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const body = (await req.json()) as Body;
    requireFields(body, ["scroll_id"]);
    const password = body.password ?? body.magic_password;

    const service = createServiceClient();
    // RPCs that read auth.uid() must run as the verified user, not service role.
    const userClient = createUserClient(authHeader);

    const { data: scroll, error: scrollErr } = await service
      .from("scrolls")
      .select(
        "id, sender_id, recipient_id, title, unlock_at, has_password, created_at",
      )
      .eq("id", body.scroll_id)
      .maybeSingle();

    if (scrollErr || !scroll) {
      throw new AppError("not_found", "Scroll not found", 404);
    }

    // 3. Recipient only
    if (scroll.recipient_id !== me) {
      throw new AppError("forbidden", "Only the recipient can open this scroll", 403);
    }

    // Ensure state rows exist (idempotent) then check recipient soft-delete.
    await service.rpc("ensure_scroll_party_states", { p_scroll_id: scroll.id });

    const { data: recipientState, error: stateErr } = await service
      .from("scroll_recipient_states")
      .select(
        "scroll_id, recipient_id, is_read, is_saved, is_favorite, first_opened_at, last_opened_at, opened_count, deleted_at",
      )
      .eq("scroll_id", scroll.id)
      .eq("recipient_id", me)
      .maybeSingle();

    if (stateErr || !recipientState) {
      throw new AppError("not_found", "Recipient scroll state not found", 404);
    }

    // 4. Recipient has not deleted their copy
    if (recipientState.deleted_at) {
      throw new AppError("deleted", "This scroll is no longer available", 410);
    }

    // 5. Blocks
    const { data: blocked } = await service.rpc("is_blocked", {
      a: me,
      b: scroll.sender_id,
    });
    if (blocked) {
      throw new AppError("blocked", "Cannot open scroll — a block exists", 403);
    }

    // 6. unlock_at vs server now
    const unlockAt = new Date(scroll.unlock_at as string);
    const now = new Date();
    if (unlockAt.getTime() > now.getTime()) {
      throw new AppError("locked", "This scroll is not unlocked yet", 403);
    }

    // Load encrypted contents (service role only — never returned)
    const { data: contents, error: contentErr } = await service
      .from("scroll_contents")
      .select("ciphertext, nonce, password_hash, encryption_version")
      .eq("scroll_id", scroll.id)
      .maybeSingle();

    if (contentErr || !contents) {
      throw new AppError("missing_contents", "Scroll contents unavailable", 500);
    }

    // 7–8. Password rate limit + verify
    if (scroll.has_password) {
      await assertNotRateLimited(service, scroll.id as string, me);

      if (!password) {
        throw new AppError("password_required", "Password required", 401);
      }

      const ok = await verifyPassword(
        password,
        contents.password_hash as string,
      );
      await recordAttempt(service, scroll.id as string, me, ok);

      if (!ok) {
        throw new AppError("invalid_password", "Incorrect password", 401);
      }
    }

    // 9. Decrypt — do not return early; state update happens next
    let message: string;
    try {
      message = await decryptMessage(
        contents.ciphertext as string,
        contents.nonce as string,
      );
    } catch (e) {
      console.error("decrypt failed", e);
      throw new AppError("decrypt_failed", "Could not decrypt message", 500);
    }

    // 10. Authoritative recipient-state update (also syncs legacy scrolls fields)
    const { data: updatedState, error: markErr } = await userClient.rpc(
      "mark_recipient_scroll_opened",
      { p_scroll_id: scroll.id },
    );
    if (markErr || !updatedState) {
      console.error(markErr);
      throw new AppError("update_failed", "Could not mark scroll opened", 500);
    }

    const stateRow = Array.isArray(updatedState) ? updatedState[0] : updatedState;

    // 11. Return message + safe metadata (never ciphertext / hash)
    return jsonResponse({
      scroll: {
        id: scroll.id,
        sender_id: scroll.sender_id,
        recipient_id: scroll.recipient_id,
        title: scroll.title,
        unlock_at: scroll.unlock_at,
        has_password: scroll.has_password,
        created_at: scroll.created_at,
        is_read: true,
        is_saved: true,
        is_favorite: Boolean(stateRow?.is_favorite),
        first_opened_at: stateRow?.first_opened_at ?? null,
        last_opened_at: stateRow?.last_opened_at ?? null,
        opened_count: Number(stateRow?.opened_count ?? 0),
        is_opened: true,
        opened_at: stateRow?.first_opened_at ?? null,
      },
      message,
      ephemeral: Boolean(scroll.has_password),
    });
  } catch (err) {
    return errorResponse(err);
  }
});
