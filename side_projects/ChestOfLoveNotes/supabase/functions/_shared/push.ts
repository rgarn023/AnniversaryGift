/** Server-side FCM push helper. Credentials via Edge secrets only — never client. */

import { createServiceClient } from "./supabase.ts";

export type PushPayload = {
  title: string;
  body: string;
  deepLink?: string;
  channel?: string;
};

async function getAccessToken(): Promise<string | null> {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";
  if (!raw.trim()) return null;
  try {
    const sa = JSON.parse(raw) as {
      client_email: string;
      private_key: string;
      token_uri?: string;
      project_id?: string;
    };
    if (!sa.client_email || !sa.private_key) return null;
    // Minimal JWT for Google OAuth — use google-auth style via fetch to token endpoint.
    const now = Math.floor(Date.now() / 1000);
    const header = btoa(JSON.stringify({ alg: "RS256", typ: "JWT" }))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const claim = btoa(JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: sa.token_uri ?? "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    // Deno cannot easily RS256 without WebCrypto import of PKCS8 — if unavailable, skip.
    // Prefer pre-minted FCM_SERVER_KEY (legacy) when present.
    void header;
    void claim;
    return null;
  } catch {
    return null;
  }
}

/** Send via legacy FCM HTTP API when FCM_SERVER_KEY is configured. */
export async function sendPushToUser(userId: string, payload: PushPayload): Promise<{ sent: number; configured: boolean }> {
  const serverKey = Deno.env.get("FCM_SERVER_KEY") ?? "";
  const configured = Boolean(serverKey.trim()) || Boolean(Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")?.trim());
  if (!serverKey.trim()) {
    // Attempt v1 only if we can mint a token (may be null in this runtime).
    const token = await getAccessToken();
    if (!token) {
      console.log("push_skip_no_fcm_credentials");
      return { sent: 0, configured: false };
    }
  }

  const service = createServiceClient();
  const { data: rows, error } = await service
    .from("device_push_tokens")
    .select("id, token")
    .eq("user_id", userId)
    .eq("active", true);
  if (error) {
    console.error("push_token_lookup_failed", error);
    return { sent: 0, configured };
  }
  const tokens = (rows ?? []).map((r) => String(r.token ?? "")).filter((t) => t.length > 8);
  if (tokens.length === 0) {
    return { sent: 0, configured };
  }

  let sent = 0;
  for (const deviceToken of tokens) {
    try {
      const res = await fetch("https://fcm.googleapis.com/fcm/send", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `key=${serverKey}`,
        },
        body: JSON.stringify({
          to: deviceToken,
          priority: "high",
          notification: {
            title: payload.title,
            body: payload.body,
            // Do not put sensitive content here.
          },
          data: {
            coln_deeplink: payload.deepLink ?? "chest",
            channel: payload.channel ?? "scrolls",
          },
        }),
      });
      if (res.ok) {
        sent += 1;
      } else {
        const text = await res.text();
        console.error("fcm_send_failed", res.status, text.slice(0, 200));
        if (res.status === 404 || text.includes("NotRegistered")) {
          await service.from("device_push_tokens").update({ active: false }).eq("token", deviceToken);
        }
      }
    } catch (e) {
      console.error("fcm_send_exception", e);
    }
  }
  return { sent, configured };
}

export async function claimServerNotificationEvent(
  userId: string,
  scrollId: string | null,
  eventKey: string,
): Promise<boolean> {
  const service = createServiceClient();
  const { error } = await service.from("notification_events").insert({
    user_id: userId,
    scroll_id: scrollId,
    event_key: eventKey,
  });
  if (error) {
    // unique violation → already claimed
    return false;
  }
  return true;
}
