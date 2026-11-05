// RETIRED 2026-11-04 (Thomas): generate-daily-report was the Expo app's daily report, already retired in FunctionAlps-APP (Mistral-Small).
// Nothing live calls it: the native iOS app replaced the Expo app, and the members site,
// STUDIO, the website and the clinical dashboard never did. It is deployed as this stub so
// nothing can reach an AI provider through it. The original source stays in git history
// (FunctionAlps-APP/supabase/functions/generate-daily-report/ where it lived there).
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
}

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  return new Response(JSON.stringify({ error: "gone", detail: "generate-daily-report is retired" }), {
    status: 410,
    headers: { ...CORS, "Content-Type": "application/json" },
  })
})
