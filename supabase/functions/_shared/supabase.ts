import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!

function getBearerToken(req: Request): string | null {
  const authHeader = req.headers.get("Authorization")
  if (!authHeader?.startsWith("Bearer ")) return null
  return authHeader.slice("Bearer ".length)
}

/** Every read runs as the CALLER: own-rows RLS is the security boundary, never a service key. */
export function createUserScopedClient(req: Request): SupabaseClient {
  const token = getBearerToken(req)
  return createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: token ? { Authorization: `Bearer ${token}` } : {} },
    auth: { persistSession: false, autoRefreshToken: false },
  })
}
