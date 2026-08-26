import { handleCors, jsonResponse } from "../_shared/cors.ts";
import { requireUser, callerId, requirePrivateMember } from "../_shared/auth.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { AppError, errorResponse, requireFields } from "../_shared/errors.ts";
import {
  encryptMagicPasswordForSender,
  encryptMessage,
  hashPassword,
} from "../_shared/crypto.ts";
import { claimServerNotificationEvent, sendPushToUser } from "../_shared/push.ts";

interface Body {
  recipient_id: string;
  message: string;
  title?: string;
  unlock_at?: string;
  password?: string;
  /** Optional Location Lock — recipient must be near lat/lng to open. */
  has_location_lock?: boolean;
  location_name?: string;
  location_address?: string;
  location_lat?: number;
  location_lng?: number;
  location_radius_m?: number;
  /** Optional Activity Lock — travel cumulative km after Start Challenge. */
  activity_lock_enabled?: boolean;
  activity_target_km?: number;
  /** Optional Focus Lock — uninterrupted focus hours. */
  focus_lock_enabled?: boolean;
  focus_duration_hours?: number;
  /** Pending photo uploads from prepare-attachment-uploads (max 5). */
  attachments?: Array<{
    path: string;
    mime_type?: string;
    width?: number;
    height?: number;
    byte_size?: number;
    sort_order?: number;
  }>;
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

    // Self-send is allowed for end-to-end lock testing (sender == recipient).
    // Locks are NOT bypassed when recipient is the sender.
    const isSelfSend = body.recipient_id === me;

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

    let hasLocationLock = Boolean(body.has_location_lock);
    let locationName = (body.location_name ?? "").trim().slice(0, 120);
    let locationAddress = (body.location_address ?? "").trim().slice(0, 240);
    let locationLat: number | null = null;
    let locationLng: number | null = null;
    let locationRadiusM = 500;
    if (hasLocationLock) {
      const lat = Number(body.location_lat);
      const lng = Number(body.location_lng);
      const radius = Number(body.location_radius_m ?? 500);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        throw new AppError(
          "invalid_location",
          "Select a location from the search results or choose one on the map.",
          400,
        );
      }
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        throw new AppError("invalid_location", "Location coordinates out of range", 400);
      }
      if (!Number.isFinite(radius) || radius < 1 || radius > 10000) {
        throw new AppError("invalid_location", "Location radius must be 1–10000 meters", 400);
      }
      if (!locationName) {
        locationName = "a set place";
      }
      // location_address is its own column (migration 20260807233000) — do not fold into name.
      locationLat = lat;
      locationLng = lng;
      locationRadiusM = Math.round(radius);
    } else {
      locationName = "";
      locationAddress = "";
    }

    let activityLockEnabled = Boolean(body.activity_lock_enabled);
    let activityTargetKm = 0;
    if (activityLockEnabled) {
      const km = Number(body.activity_target_km ?? 0);
      if (!Number.isFinite(km) || km < 1 || km > 100) {
        throw new AppError(
          "invalid_activity",
          "Activity distance must be between 1 and 100 km",
          400,
        );
      }
      activityTargetKm = Math.round(km * 100) / 100;
    }

    let focusLockEnabled = Boolean(body.focus_lock_enabled);
    let focusDurationHours = 0;
    if (focusLockEnabled) {
      const hours = Number(body.focus_duration_hours ?? 0);
      if (!Number.isFinite(hours) || hours < 1 || hours > 24) {
        throw new AppError(
          "invalid_focus",
          "Focus time must be between 1 and 24 hours",
          400,
        );
      }
      focusDurationHours = Math.round(hours);
    }

    if (!isSelfSend) {
      // Production sends must target the sender's active Person only.
      const { data: personId } = await service.rpc("get_active_person_id", { p_user: me });
      if (!personId || String(personId) !== String(body.recipient_id)) {
        throw new AppError(
          "not_person",
          "You can only send scrolls to your Person",
          403,
        );
      }

      const { data: friends } = await service.rpc("are_friends", {
        a: me,
        b: body.recipient_id,
      });
      if (!friends) {
        throw new AppError("not_friends", "You can only send scrolls to your Person", 403);
      }

      const { data: blocked } = await service.rpc("is_blocked", {
        a: me,
        b: body.recipient_id,
      });
      if (blocked) {
        throw new AppError("blocked", "Cannot send scroll — a block exists", 403);
      }
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
        has_location_lock: hasLocationLock,
        location_name: locationName,
        location_address: locationAddress,
        location_lat: locationLat,
        location_lng: locationLng,
        location_radius_m: locationRadiusM,
        activity_lock_enabled: activityLockEnabled,
        activity_target_km: activityTargetKm,
        focus_lock_enabled: focusLockEnabled,
        focus_duration_hours: focusDurationHours,
      })
      .select(
        "id, sender_id, recipient_id, title, unlock_at, has_password, has_location_lock, location_name, location_address, location_lat, location_lng, location_radius_m, activity_lock_enabled, activity_target_km, focus_lock_enabled, focus_duration_hours, created_at",
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


    // Attach pending photos (must already exist in private storage under pending/{me}/…).
    const pending = Array.isArray(body.attachments) ? body.attachments.slice(0, 5) : [];
    const attachedMeta: Array<Record<string, unknown>> = [];
    if (pending.length > 0) {
      for (let i = 0; i < pending.length; i++) {
        const item = pending[i];
        const srcPath = String(item.path ?? "");
        const prefix = `pending/${me}/`;
        if (!srcPath.startsWith(prefix)) {
          await service.from("scrolls").update({ deleted_at: new Date().toISOString() }).eq("id", scroll.id);
          throw new AppError("invalid_attachments", "Invalid attachment upload path", 400);
        }
        const mime = String(item.mime_type ?? "image/jpeg");
        const ext = mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg";
        const destPath = `${me}/${scroll.id}/${i}.${ext}`;
        const { error: moveErr } = await service.storage
          .from("scroll-attachments")
          .move(srcPath, destPath);
        if (moveErr) {
          console.error(moveErr);
          await service.storage.from("scroll-attachments").remove(pending.map((p) => String(p.path ?? "")).filter(Boolean));
          await service.from("scrolls").update({ deleted_at: new Date().toISOString() }).eq("id", scroll.id);
          throw new AppError("attachment_failed", "Photo upload could not be finalized. Please try again.", 500);
        }
        const row = {
          scroll_id: scroll.id,
          storage_path: destPath,
          mime_type: mime,
          width: Number.isFinite(Number(item.width)) ? Math.round(Number(item.width)) : null,
          height: Number.isFinite(Number(item.height)) ? Math.round(Number(item.height)) : null,
          byte_size: Number.isFinite(Number(item.byte_size)) ? Math.round(Number(item.byte_size)) : null,
          sort_order: Number.isFinite(Number(item.sort_order)) ? Math.round(Number(item.sort_order)) : i,
        };
        const { error: attErr } = await service.from("scroll_attachments").insert(row);
        if (attErr) {
          console.error(attErr);
          await service.storage.from("scroll-attachments").remove([destPath]);
          await service.from("scrolls").update({ deleted_at: new Date().toISOString() }).eq("id", scroll.id);
          throw new AppError("attachment_failed", "Could not save photo attachments.", 500);
        }
        attachedMeta.push({
          storage_path: destPath,
          mime_type: mime,
          sort_order: row.sort_order,
        });
      }
    }

    // Recipient push — display name only; never body / password / coordinates.
    try {
      const { data: senderProfile } = await service
        .from("profiles")
        .select("display_name")
        .eq("id", me)
        .maybeSingle();
      const fromName = String(senderProfile?.display_name ?? "").trim();
      const eventKey = `new_scroll:${scroll.id}`;
      if (await claimServerNotificationEvent(String(body.recipient_id), String(scroll.id), eventKey)) {
        const bodyText = fromName
          ? `You received a new scroll from ${fromName}.`
          : "You received a new scroll.";
        await sendPushToUser(String(body.recipient_id), {
          title: "New Scroll",
          body: bodyText,
          deepLink: `chest:${scroll.id}`,
          channel: "scrolls",
        });
      }
    } catch (pushErr) {
      console.error("push_after_send_failed", pushErr);
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
        has_location_lock: Boolean(scroll.has_location_lock),
        location_name: scroll.location_name ?? "",
        location_address: scroll.location_address ?? "",
        location_lat: scroll.location_lat ?? null,
        location_lng: scroll.location_lng ?? null,
        location_radius_m: Number(scroll.location_radius_m ?? 500),
        created_at: scroll.created_at,
        is_opened: false,
        attachment_count: attachedMeta.length,
      },
      attachments: attachedMeta,
    });
  } catch (err) {
    return errorResponse(err);
  }
});
