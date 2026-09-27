import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!

function getBearerToken(req: Request): string | null {
  const authHeader = req.headers.get("Authorization")
  if (!authHeader?.startsWith("Bearer ")) return null
  return authHeader.slice("Bearer ".length)
}

export function createUserScopedClient(req: Request): SupabaseClient {
  const token = getBearerToken(req)
  return createClient(SUPABASE_URL, ANON_KEY, {
    global: {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    },
  })
}

export function createServiceRoleClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
}

export async function resolvePatientId(req: Request, fallbackPatientId?: string | null): Promise<string | null> {
  if (fallbackPatientId) return fallbackPatientId

  const token = getBearerToken(req)
  if (!token) return null

  const serviceClient = createServiceRoleClient()
  const {
    data: { user },
    error: authError,
  } = await serviceClient.auth.getUser(token)

  if (authError || !user) return null

  const { data, error } = await serviceClient
    .from("patients")
    .select("id")
    .eq("auth_user_id", user.id)
    .maybeSingle()

  if (error) return null
  return data?.id ?? null
}
