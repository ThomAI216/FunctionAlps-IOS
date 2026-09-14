// legal-page — PUBLIC (verify_jwt off): the practice's legal documents as plain, readable HTML pages, straight
// from `consent_definitions` (the CURRENT approved version, both locales). Vendors' developer portals (WHOOP,
// Oura, Withings…) require a public privacy-policy URL; App Store Connect and the website link here too.
//
//   GET /legal-page/privacy         → Privacy Notice          (consent_key privacy_policy)
//   GET /legal-page/terms           → Terms of Service        (consent_key terms_of_use)
//   GET /legal-page/legal-notice    → Legal Notice            (consent_key legal_notice)
//   GET /legal-page/health-data     → Health-data processing  (consent_key health_data_processing)
//   GET /legal-page/ai              → How AI is used          (consent_key ai_analysis)
//   ?lang=fr | en (default: Accept-Language, then en). Anon read is allowed by RLS only for approved, current rows.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"
import { marked } from "npm:marked@15"

const PAGES: Record<string, string> = {
  privacy: "privacy_policy", terms: "terms_of_use", "legal-notice": "legal_notice", "health-data": "health_data_processing", ai: "ai_analysis",
}

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string))

function shell(title: string, bodyHtml: string, lang: string, slug: string, version: string, effective: string | null): string {
  const other = lang === "fr" ? "en" : "fr"
  const otherLabel = lang === "fr" ? "English" : "Français"
  const updated = effective ? new Date(effective).toLocaleDateString(lang === "fr" ? "fr-CH" : "en-GB", { year: "numeric", month: "long", day: "numeric" }) : ""
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} · FunctionAlps</title><meta name="robots" content="index,follow">
<style>
:root{color-scheme:light}body{margin:0;background:#f4f7f4;color:#1f2a22;font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
main{max-width:760px;margin:0 auto;padding:40px 22px 80px}header{display:flex;justify-content:space-between;align-items:baseline;gap:16px;margin-bottom:28px}
header .brand{font-weight:700;letter-spacing:.3px;color:#2e5438;text-decoration:none}header a.lang{font-size:14px;color:#4a8a5c}
h1{font-size:30px;line-height:1.2;margin:0 0 6px}h2{font-size:21px;margin:34px 0 10px}h3{font-size:17px;margin:26px 0 8px}
p,li{font-size:16px}ul,ol{padding-left:22px}a{color:#2e5438}hr{border:0;border-top:1px solid #d9e3db;margin:32px 0}
.meta{color:#5f6f63;font-size:14px;margin-bottom:26px}footer{margin-top:48px;color:#5f6f63;font-size:13px}
</style></head><body><main>
<header><a class="brand" href="./${slug}?lang=${lang}">FunctionAlps</a><a class="lang" href="./${slug}?lang=${other}">${otherLabel}</a></header>
<h1>${esc(title)}</h1><div class="meta">${esc(version)}${updated ? ` · ${lang === "fr" ? "en vigueur depuis le" : "effective"} ${esc(updated)}` : ""}</div>
${bodyHtml}
<footer>FunctionAlps · CM Functional Health · ${lang === "fr" ? "Document en vigueur, servi depuis le registre des consentements." : "Current document, served from the consent register."}</footer>
</main></body></html>`
}

Deno.serve(async (req) => {
  const url = new URL(req.url)
  const slug = url.pathname.split("/").filter(Boolean).pop() ?? ""
  const key = PAGES[slug]
  if (!key) {
    const list = Object.keys(PAGES).map((s) => `<li><a href="./${s}">${s}</a></li>`).join("")
    return new Response(`<!doctype html><meta charset="utf-8"><title>FunctionAlps · Legal</title><main style="font-family:sans-serif;max-width:640px;margin:40px auto"><h1>FunctionAlps — legal documents</h1><ul>${list}</ul></main>`, { status: slug ? 404 : 200, headers: { "Content-Type": "text/html; charset=utf-8" } })
  }
  const accept = req.headers.get("Accept-Language") ?? ""
  const lang = (url.searchParams.get("lang") ?? (accept.toLowerCase().startsWith("fr") ? "fr" : "en")) === "fr" ? "fr" : "en"
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } })
  const { data, error } = await db.from("consent_definitions").select("title,body_md,version,effective_from")
    .eq("consent_key", key).eq("locale", lang).eq("review_status", "approved").is("superseded_at", null).maybeSingle()
  if (error || !data) return new Response("document unavailable", { status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" } })
  const bodyHtml = await marked.parse(String(data.body_md), { gfm: true })
  return new Response(shell(String(data.title), bodyHtml, lang, slug, String(data.version), (data.effective_from as string | null) ?? null), {
    status: 200, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=300", "X-Content-Type-Options": "nosniff" },
  })
})
