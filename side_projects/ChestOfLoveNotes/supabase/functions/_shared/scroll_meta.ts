/** Safe metadata projections — never include ciphertext, nonce, password hash, or plaintext. */

export type ProfileSafe = {
  id: string;
  username: string;
  display_name: string;
  friend_code: string;
  avatar_url: string | null;
};

export function profileSafe(p: Record<string, unknown> | null | undefined): ProfileSafe | null {
  if (!p || typeof p.id !== "string") return null;
  return {
    id: p.id,
    username: String(p.username ?? ""),
    display_name: String(p.display_name ?? ""),
    friend_code: String(p.friend_code ?? ""),
    avatar_url: (p.avatar_url as string | null) ?? null,
  };
}

export function recipientScrollSafe(args: {
  scroll: Record<string, unknown>;
  state: Record<string, unknown>;
  sender?: ProfileSafe | null;
  nowMs?: number;
}) {
  const now = args.nowMs ?? Date.now();
  const unlockAt = String(args.scroll.unlock_at ?? "");
  const isRead = Boolean(args.state.is_read);
  return {
    id: args.scroll.id,
    sender_id: args.scroll.sender_id,
    recipient_id: args.scroll.recipient_id,
    title: args.scroll.title,
    created_at: args.scroll.created_at,
    unlock_at: unlockAt,
    has_password: Boolean(args.scroll.has_password),
    has_location_lock: Boolean(args.scroll.has_location_lock),
    location_name: String(args.scroll.location_name ?? ""),
    location_address: String(args.scroll.location_address ?? ""),
    location_lat: args.scroll.location_lat ?? null,
    location_lng: args.scroll.location_lng ?? null,
    location_radius_m: Number(args.scroll.location_radius_m ?? 500),
    is_read: isRead,
    is_saved: Boolean(args.state.is_saved),
    is_favorite: Boolean(args.state.is_favorite),
    first_opened_at: args.state.first_opened_at ?? null,
    last_opened_at: args.state.last_opened_at ?? null,
    opened_count: Number(args.state.opened_count ?? 0),
    is_unlockable: unlockAt ? new Date(unlockAt).getTime() <= now : false,
    // Compatibility aliases for older clients
    is_opened: isRead,
    opened_at: args.state.first_opened_at ?? null,
    sender: args.sender ?? null,
  };
}

export function sentScrollSafe(args: {
  scroll: Record<string, unknown>;
  senderState: Record<string, unknown>;
  recipientState?: Record<string, unknown> | null;
  recipient?: ProfileSafe | null;
}) {
  const rs = args.recipientState ?? null;
  const isRead = Boolean(rs?.is_read);
  return {
    id: args.scroll.id,
    sender_id: args.scroll.sender_id,
    recipient_id: args.scroll.recipient_id,
    title: args.scroll.title,
    created_at: args.scroll.created_at,
    unlock_at: args.scroll.unlock_at,
    has_password: Boolean(args.scroll.has_password),
    has_location_lock: Boolean(args.scroll.has_location_lock),
    location_name: String(args.scroll.location_name ?? ""),
    location_address: String(args.scroll.location_address ?? ""),
    location_lat: args.scroll.location_lat ?? null,
    location_lng: args.scroll.location_lng ?? null,
    location_radius_m: Number(args.scroll.location_radius_m ?? 500),
    recipient_opened: isRead,
    first_opened_at: rs?.first_opened_at ?? null,
    last_opened_at: rs?.last_opened_at ?? null,
    opened_count: Number(rs?.opened_count ?? 0),
    // Compatibility
    is_opened: isRead,
    opened_at: rs?.first_opened_at ?? null,
    recipient: args.recipient ?? null,
  };
}

/** Strip any accidental sensitive keys from an object before JSON responses. */
const FORBIDDEN_KEYS = new Set([
  "ciphertext",
  "nonce",
  "password_hash",
  "password",
  "magic_password",
  "encryption_key",
  "MESSAGE_ENCRYPTION_KEY",
  "iv",
  "message",
]);

export function assertNoSensitiveKeys(value: unknown, path = "root"): void {
  if (Array.isArray(value)) {
    value.forEach((v, i) => assertNoSensitiveKeys(v, `${path}[${i}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (FORBIDDEN_KEYS.has(k)) {
        throw new Error(`Sensitive key leaked in response at ${path}.${k}`);
      }
      assertNoSensitiveKeys(v, `${path}.${k}`);
    }
  }
}
