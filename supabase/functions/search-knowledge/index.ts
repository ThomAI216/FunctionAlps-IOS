// RETIRED 2026-11-04 (Thomas): search-knowledge was a knowledge_chunks vector search wrapper nothing calls (STUDIO uses the RPC directly).
// Nothing live calls it: the native iOS app replaced the Expo app, and the members site,
// STUDIO, the website and the clinical dashboard never did. It is deployed as this stub so
// nothing can reach an AI provider through it. The original source stays in git history
// (FunctionAlps-APP/supabase/functions/search-knowledge/ where it lived there).
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
}

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  return new Response(JSON.stringify({ error: "gone", detail: "search-knowledge is retired" }), {
    status: 410,
    headers: { ...CORS, "Content-Type": "application/json" },
  })
})
