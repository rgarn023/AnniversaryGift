import { createServiceClient, createUserClient } from "./supabase.ts";
import { AppError } from "./errors.ts";
import type { User } from "npm:@supabase/supabase-js@2";

export async function requireUser(req: Request): Promise<{
  user: User;
  authHeader: string;
}> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.toLowerCase().startsWith("bearer ")) {
    throw new AppError("unauthorized", "Missing or invalid Authorization header", 401);
  }

  const client = createUserClient(authHeader);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw new AppError("unauthorized", "Invalid or expired JWT", 401);
  }

  return { user: data.user, authHeader };
}

/** Always derive caller id from the JWT — never trust body.sender_id. */
export function callerId(user: User): string {
  return user.id;
}

/**
 * Require an active private-app membership.
 * Uses service-role only to evaluate the membership helper; never returns secrets.
 */
export async function requirePrivateMember(user: User): Promise<void> {
  const service = createServiceClient();
  const { data, error } = await service.rpc("is_active_private_app_member", {
    p_user_id: user.id,
  });
  if (error) {
    throw new AppError("forbidden", "Unable to verify private membership", 403);
  }
  if (data !== true) {
    throw new AppError(
      "forbidden",
      "This account is not invited to the private Chest of Love Notes app",
      403,
    );
  }
}
