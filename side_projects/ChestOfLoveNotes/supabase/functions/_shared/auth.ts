import { createUserClient } from "./supabase.ts";
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
