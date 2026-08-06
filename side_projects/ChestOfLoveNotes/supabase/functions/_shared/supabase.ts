import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export type Database = Record<string, unknown>;

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

/** Anon / user-scoped client (respects RLS). Pass the caller's JWT. */
export function createUserClient(authHeader: string): SupabaseClient {
  const url = requireEnv("SUPABASE_URL");
  const anonKey = requireEnv("SUPABASE_ANON_KEY");
  return createClient(url, anonKey, {
    global: {
      headers: { Authorization: authHeader },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}

/**
 * Service-role client — bypasses RLS.
 * Use ONLY server-side for scroll_contents and privileged writes.
 * Never expose the service role key to clients.
 */
export function createServiceClient(): SupabaseClient {
  const url = requireEnv("SUPABASE_URL");
  const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  return createClient(url, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}
