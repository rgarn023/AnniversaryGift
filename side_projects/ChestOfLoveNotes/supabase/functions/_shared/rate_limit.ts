/**
 * Password-attempt rate limiting backed by scroll_open_attempts.
 *
 * Defaults: max 5 failed attempts per scroll+user in a 15-minute window.
 * Edge functions should call assertNotRateLimited before verifyPassword,
 * and recordAttempt after each try (success or failure).
 *
 * Note: an in-memory Map could be used as a soft first line of defense in a
 * single isolate, but DB-backed attempts survive cold starts and scale across
 * workers — prefer the table.
 */

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { AppError } from "./errors.ts";

export const DEFAULT_MAX_FAILURES = 5;
export const DEFAULT_WINDOW_MINUTES = 15;

export async function countRecentFailures(
  service: SupabaseClient,
  scrollId: string,
  userId: string,
  windowMinutes = DEFAULT_WINDOW_MINUTES,
): Promise<number> {
  const { data, error } = await service.rpc("count_recent_failed_open_attempts", {
    p_scroll_id: scrollId,
    p_user_id: userId,
    p_window_minutes: windowMinutes,
  });
  if (error) {
    console.error("rate_limit count error", error);
    throw new AppError("rate_limit_check_failed", "Could not check rate limit", 500);
  }
  return typeof data === "number" ? data : 0;
}

export async function assertNotRateLimited(
  service: SupabaseClient,
  scrollId: string,
  userId: string,
  maxFailures = DEFAULT_MAX_FAILURES,
  windowMinutes = DEFAULT_WINDOW_MINUTES,
): Promise<void> {
  const failures = await countRecentFailures(service, scrollId, userId, windowMinutes);
  if (failures >= maxFailures) {
    throw new AppError(
      "rate_limited",
      `Too many password attempts. Try again in about ${windowMinutes} minutes.`,
      429,
    );
  }
}

export async function recordAttempt(
  service: SupabaseClient,
  scrollId: string,
  userId: string,
  success: boolean,
): Promise<void> {
  const { error } = await service.from("scroll_open_attempts").insert({
    scroll_id: scrollId,
    user_id: userId,
    success,
  });
  if (error) {
    console.error("recordAttempt failed", error);
  }
}
