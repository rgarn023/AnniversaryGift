/**
 * Message encryption + password hashing helpers.
 *
 * Encryption: AES-256-GCM with MESSAGE_ENCRYPTION_KEY
 *   - Key must be 32 bytes, provided as base64 or hex via env.
 *
 * Password hashing:
 *   - Preferred: Argon2id (when available in the runtime).
 *   - Fallback: bcrypt via npm:bcrypt (used here for Deno Deploy / Edge compatibility).
 *
 * Documented preference order for operators:
 *   1) Argon2id (OWASP) if you swap in a WASM/native module
 *   2) bcrypt cost >= 10 (current fallback via bcryptjs — pure JS for Deno Edge)
 */

import bcrypt from "npm:bcryptjs@2.4.3";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function parseEncryptionKey(): Uint8Array<ArrayBuffer> {
  const raw = Deno.env.get("MESSAGE_ENCRYPTION_KEY");
  if (!raw) {
    throw new Error("MESSAGE_ENCRYPTION_KEY is not set");
  }

  // Prefer base64 (44 chars for 32 bytes) else hex (64 chars).
  let key: Uint8Array<ArrayBuffer>;
  if (/^[0-9a-fA-F]{64}$/.test(raw)) {
    key = Uint8Array.from(raw.match(/.{1,2}/g)!.map((b) => parseInt(b, 16)));
  } else {
    const bin = atob(raw);
    key = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) key[i] = bin.charCodeAt(i);
  }

  if (key.length !== 32) {
    throw new Error("MESSAGE_ENCRYPTION_KEY must decode to 32 bytes");
  }
  return key;
}

function bytesToBase64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function base64ToBytes(b64: string): Uint8Array<ArrayBuffer> {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function asBufferSource(bytes: Uint8Array): BufferSource {
  return bytes as unknown as BufferSource;
}

export interface EncryptedPayload {
  ciphertext: string; // base64(ciphertext || authTag)
  nonce: string; // base64(12-byte IV)
  encryption_version: number;
}

export async function encryptMessage(plaintext: string): Promise<EncryptedPayload> {
  const keyBytes = parseEncryptionKey();
  const key = await crypto.subtle.importKey(
    "raw",
    asBufferSource(keyBytes),
    { name: "AES-GCM" },
    false,
    ["encrypt"],
  );
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const cipherBuf = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: asBufferSource(nonce) },
    key,
    encoder.encode(plaintext),
  );
  return {
    ciphertext: bytesToBase64(new Uint8Array(cipherBuf)),
    nonce: bytesToBase64(nonce),
    encryption_version: 1,
  };
}

export async function decryptMessage(
  ciphertextB64: string,
  nonceB64: string,
): Promise<string> {
  const keyBytes = parseEncryptionKey();
  const key = await crypto.subtle.importKey(
    "raw",
    asBufferSource(keyBytes),
    { name: "AES-GCM" },
    false,
    ["decrypt"],
  );
  const plainBuf = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: asBufferSource(base64ToBytes(nonceB64)) },
    key,
    asBufferSource(base64ToBytes(ciphertextB64)),
  );
  return decoder.decode(plainBuf);
}

const BCRYPT_ROUNDS = 10;

/** Hash a scroll password. Min 4 / max 64 chars enforced by callers. */
export async function hashPassword(password: string): Promise<string> {
  // bcryptjs fallback — Argon2id preferred when available in production.
  // hashSync keeps Edge cold-starts simple (passwords are short, cost 10).
  return bcrypt.hashSync(password, BCRYPT_ROUNDS);
}

export async function verifyPassword(
  password: string,
  passwordHash: string,
): Promise<boolean> {
  try {
    return bcrypt.compareSync(password, passwordHash);
  } catch {
    return false;
  }
}
