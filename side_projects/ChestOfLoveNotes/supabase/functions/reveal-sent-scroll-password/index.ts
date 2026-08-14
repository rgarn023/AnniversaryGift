import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";
import { decryptMagicPasswordForSender } from "../_shared/crypto.ts";

interface Body {
  scroll_id: string;
}

/**
 * Reveal the sender's recoverable Magic Password for a sent scroll.
 * Recipient / unrelated users always receive 403.
 * Never returns ciphertext, IV, key, or password_hash.
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
    const body = (await req.json()) as Body;
    requireFields(body, ["scroll_id"]);

    const service = createServiceClient();

    const { data: scroll, error: scrollErr } = await service
      .from("scrolls")
      .select("id, sender_id, has_password")
      .eq("id", body.scroll_id)
      .maybeSingle();

    if (scrollErr) {
      console.error(scrollErr);
      throw new AppError("fetch_failed", "Could not load scroll", 500);
    }
    if (!scroll) {
      throw new AppError("not_found", "Scroll not found", 404);
    }
    if (scroll.sender_id !== me) {
      throw new AppError("forbidden", "Only the original sender may reveal this password", 403);
    }
    if (!scroll.has_password) {
      throw new AppError("not_password_protected", "This scroll has no Magic Password", 400);
    }

    // Sender soft-delete makes recovery unavailable.
    const { data: senderState, error: stateErr } = await service
      .from("scroll_sender_states")
      .select("scroll_id, sender_id, deleted_at")
      .eq("scroll_id", body.scroll_id)
      .eq("sender_id", me)
      .maybeSingle();

    if (stateErr) {
      console.error(stateErr);
      throw new AppError("fetch_failed", "Could not load sender state", 500);
    }
    if (!senderState || senderState.deleted_at != null) {
      throw new AppError(
        "forbidden",
        "Password recovery is unavailable for this sent scroll",
        403,
      );
    }

    const { data: secret, error: secretErr } = await service
      .from("scroll_sender_secrets")
      .select("encrypted_magic_password, encryption_iv, encryption_version, sender_id")
      .eq("scroll_id", body.scroll_id)
      .maybeSingle();

    if (secretErr) {
      console.error(secretErr);
      throw new AppError("fetch_failed", "Could not load recovery record", 500);
    }
    if (!secret || secret.sender_id !== me) {
      throw new AppError("not_found", "No recoverable password for this scroll", 404);
    }

    let password = "";
    try {
      password = await decryptMagicPasswordForSender(
        String(secret.encrypted_magic_password),
        String(secret.encryption_iv),
      );
    } catch (err) {
      console.error("recovery_decrypt_failed");
      throw new AppError("decrypt_failed", "Could not reveal Magic Password", 500);
    }

    // Return plaintext password only over authenticated HTTPS — never log it.
    const response = jsonResponse({
      ok: true,
      scroll_id: body.scroll_id,
      magic_password: password,
    });
    password = "";
    return response;
  } catch (err) {
    return errorResponse(err);
  }
});
