import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";
import { decryptMessage, verifyPassword } from "../_shared/crypto.ts";
import { assertNotRateLimited, recordAttempt } from "../_shared/rate_limit.ts";

interface Body {
  scroll_id: string;
  password?: string;
}

/**
 * Open-scroll check order (required):
 * 1. Auth (JWT → caller id)
 * 2. Caller is recipient
 * 3. Scroll not soft-deleted
 * 4. Not blocked (either direction)
 * 5. unlock_at <= now()
 * 6. Password rate limit (if password-protected)
 * 7. Password verify (if password-protected)
 * 8. Decrypt ciphertext
 * 9. Update opened fields
 * 10. Return plaintext message (+ metadata)
 */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    // 1. Auth
    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    const me = callerId(user);
    const body = (await req.json()) as Body;
    requireFields(body, ["scroll_id"]);

    const service = createServiceClient();

    const { data: scroll, error: scrollErr } = await service
      .from("scrolls")
      .select(
        "id, sender_id, recipient_id, title, unlock_at, has_password, is_opened, opened_at, deleted_at, created_at",
      )
      .eq("id", body.scroll_id)
      .maybeSingle();

    if (scrollErr || !scroll) {
      throw new AppError("not_found", "Scroll not found", 404);
    }

    // 2. Recipient only
    if (scroll.recipient_id !== me) {
      throw new AppError("forbidden", "Only the recipient can open this scroll", 403);
    }

    // 3. Not deleted
    if (scroll.deleted_at) {
      throw new AppError("deleted", "This scroll is no longer available", 410);
    }

    // 4. Blocks
    const { data: blocked } = await service.rpc("is_blocked", {
      a: me,
      b: scroll.sender_id,
    });
    if (blocked) {
      throw new AppError("blocked", "Cannot open scroll — a block exists", 403);
    }

    // 5. unlock_at vs now()
    const unlockAt = new Date(scroll.unlock_at as string);
    const now = new Date();
    if (unlockAt.getTime() > now.getTime()) {
      throw new AppError(
        "locked",
        "This scroll is not unlocked yet",
        403,
      );
    }

    // Load encrypted contents (service role only)
    const { data: contents, error: contentErr } = await service
      .from("scroll_contents")
      .select("ciphertext, nonce, password_hash, encryption_version")
      .eq("scroll_id", scroll.id)
      .maybeSingle();

    if (contentErr || !contents) {
      throw new AppError("missing_contents", "Scroll contents unavailable", 500);
    }

    // 6–7. Password rate limit + verify
    if (scroll.has_password) {
      await assertNotRateLimited(service, scroll.id as string, me);

      if (!body.password) {
        throw new AppError("password_required", "Password required", 401);
      }

      const ok = await verifyPassword(
        body.password,
        contents.password_hash as string,
      );
      await recordAttempt(service, scroll.id as string, me, ok);

      if (!ok) {
        throw new AppError("invalid_password", "Incorrect password", 401);
      }
    }

    // 8. Decrypt
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

    // 9. Update opened fields (idempotent if already opened)
    let openedAt = scroll.opened_at as string | null;
    if (!scroll.is_opened) {
      openedAt = now.toISOString();
      const { error: upErr } = await service
        .from("scrolls")
        .update({ is_opened: true, opened_at: openedAt })
        .eq("id", scroll.id);
      if (upErr) {
        console.error(upErr);
        throw new AppError("update_failed", "Could not mark scroll opened", 500);
      }
    }

    // 10. Return message (never return ciphertext / password_hash)
    return jsonResponse({
      scroll: {
        id: scroll.id,
        sender_id: scroll.sender_id,
        recipient_id: scroll.recipient_id,
        title: scroll.title,
        unlock_at: scroll.unlock_at,
        has_password: scroll.has_password,
        is_opened: true,
        opened_at: openedAt,
        created_at: scroll.created_at,
      },
      message,
    });
  } catch (err) {
    return errorResponse(err);
  }
});
