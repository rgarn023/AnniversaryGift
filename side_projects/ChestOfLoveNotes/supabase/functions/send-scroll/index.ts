import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";
import {
  encryptMagicPasswordForSender,
  encryptMessage,
  hashPassword,
} from "../_shared/crypto.ts";

interface Body {
  recipient_id: string;
  message: string;
  title?: string;
  unlock_at?: string;
  password?: string;
}

const MIN_PASSWORD = 4;
const MAX_PASSWORD = 64;
const MAX_MESSAGE = 8000;

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    const { user } = await requireUser(req);
    await requirePrivateMember(user);
    // Sender identity always from verified session — never trust body.sender_id.
    const me = callerId(user);
    const body = (await req.json()) as Body;
    requireFields(body, ["recipient_id", "message"]);

    if (body.recipient_id === me) {
      throw new AppError("invalid_request", "Cannot send a scroll to yourself", 400);
    }

    const message = body.message.trim();
    if (!message || message.length > MAX_MESSAGE) {
      throw new AppError(
        "invalid_message",
        `Message must be 1–${MAX_MESSAGE} characters`,
        400,
      );
    }

    let passwordHash: string | null = null;
    let hasPassword = false;
    let recoveryCipher: { ciphertext: string; iv: string; encryption_version: string } | null =
      null;
    let magicPassword: string | null = null;
    if (body.password != null && body.password !== "") {
      if (
        body.password.length < MIN_PASSWORD ||
        body.password.length > MAX_PASSWORD
      ) {
        throw new AppError(
          "invalid_password",
          `Password must be ${MIN_PASSWORD}–${MAX_PASSWORD} characters`,
          400,
        );
      }
      magicPassword = body.password;
      // Keep hash for recipient verification AND encrypted recovery for sender.
      passwordHash = await hashPassword(magicPassword);
      recoveryCipher = await encryptMagicPasswordForSender(magicPassword);
      hasPassword = true;
    }

    const unlockAt = body.unlock_at ? new Date(body.unlock_at) : new Date();
    if (Number.isNaN(unlockAt.getTime())) {
      throw new AppError("invalid_unlock_at", "unlock_at must be a valid ISO timestamp", 400);
    }

    const title = (body.title?.trim() || "A Love Note").slice(0, 120);
    const service = createServiceClient();

    const { data: friends } = await service.rpc("are_friends", {
      a: me,
      b: body.recipient_id,
    });
    if (!friends) {
      throw new AppError("not_friends", "You can only send scrolls to friends", 403);
    }

    const { data: blocked } = await service.rpc("is_blocked", {
      a: me,
      b: body.recipient_id,
    });
    if (blocked) {
      throw new AppError("blocked", "Cannot send scroll — a block exists", 403);
    }

    const encrypted = await encryptMessage(message);

    const { data: scroll, error: scrollErr } = await service
      .from("scrolls")
      .insert({
        sender_id: me,
        recipient_id: body.recipient_id,
        title,
        unlock_at: unlockAt.toISOString(),
        has_password: hasPassword,
      })
      .select(
        "id, sender_id, recipient_id, title, unlock_at, has_password, created_at",
      )
      .single();

    if (scrollErr || !scroll) {
      console.error(scrollErr);
      throw new AppError("insert_failed", "Could not create scroll", 500);
    }

    const { error: contentErr } = await service.from("scroll_contents").insert({
      scroll_id: scroll.id,
      ciphertext: encrypted.ciphertext,
      nonce: encrypted.nonce,
      password_hash: passwordHash,
      encryption_version: encrypted.encryption_version,
    });

    if (contentErr) {
      console.error(contentErr);
      // Compensating soft-hide on legacy column only; do not claim delivery.
      await service
        .from("scrolls")
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", scroll.id);
      throw new AppError("insert_failed", "Could not store encrypted message", 500);
    }

    // Sender-only recoverable Magic Password (never plaintext; never logged).
    if (hasPassword && recoveryCipher) {
      const { error: secretErr } = await service.from("scroll_sender_secrets").insert({
        scroll_id: scroll.id,
        sender_id: me,
        encrypted_magic_password: recoveryCipher.ciphertext,
        encryption_iv: recoveryCipher.iv,
        encryption_version: recoveryCipher.encryption_version,
      });
      if (secretErr) {
        console.error(secretErr);
        await service
          .from("scrolls")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", scroll.id);
        throw new AppError(
          "insert_failed",
          "Could not store sender password recovery record",
          500,
        );
      }
    }
    // Drop temporary plaintext as soon as practical.
    magicPassword = null;
    recoveryCipher = null;

    // Create recipient + sender state rows (idempotent; no duplicates).
    const { error: stateErr } = await service.rpc("ensure_scroll_party_states", {
      p_scroll_id: scroll.id,
    });
    if (stateErr) {
      console.error(stateErr);
      await service
        .from("scrolls")
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", scroll.id);
      throw new AppError(
        "insert_failed",
        "Could not initialize permanent scroll state",
        500,
      );
    }

    // Confirm both state rows exist before reporting success.
    const [{ data: rState }, { data: sState }] = await Promise.all([
      service
        .from("scroll_recipient_states")
        .select("scroll_id")
        .eq("scroll_id", scroll.id)
        .eq("recipient_id", body.recipient_id)
        .maybeSingle(),
      service
        .from("scroll_sender_states")
        .select("scroll_id")
        .eq("scroll_id", scroll.id)
        .eq("sender_id", me)
        .maybeSingle(),
    ]);

    if (!rState || !sState) {
      await service
        .from("scrolls")
        .update({ deleted_at: new Date().toISOString() })
        .eq("id", scroll.id);
      throw new AppError(
        "insert_failed",
        "Scroll state rows were not created",
        500,
      );
    }

    // Never return ciphertext / password material.
    return jsonResponse({
      scroll: {
        id: scroll.id,
        sender_id: scroll.sender_id,
        recipient_id: scroll.recipient_id,
        title: scroll.title,
        unlock_at: scroll.unlock_at,
        has_password: scroll.has_password,
        created_at: scroll.created_at,
        is_opened: false,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
});
