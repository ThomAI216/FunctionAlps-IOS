// preprocess-meal — serves ./preprocess.ts (the request and the parse live there, unit-tested).
// verify_jwt is OFF in production (listed in NO_JWT in .github/workflows/deploy-edge-functions.yml).
import { preprocessTranscript, type PreprocessInput } from "./preprocess.ts"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } })

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  try {
    const { status, body } = await preprocessTranscript((await req.json()) as PreprocessInput)
    return json(body, status)
  } catch (err) {
    console.error("[preprocess-meal]", err)
    return json({ error: "Preprocessing failed", details: String(err) }, 500)
  }
})
