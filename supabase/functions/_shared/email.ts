// supabase/functions/_shared/email.ts
//
// THE one place this project sends email from. Deno-only (imports denomailer).
// The WHO — display name, address, Reply-To — lives in ./sender-profiles.ts.
//
// Replaces four hand-rolled copies of `sendMail` that had drifted apart:
//   · delete-account / send-review-digest returned the real SMTP error
//   · daily-checkin-reminder swallowed it (`catch (_e) { return "failed" }`)
//   · q1-complete used an entirely different env convention (INFOMANIAK_SMTP_*)
// That inconsistency is why `SMTP_PORT=587` cost an afternoon to find: the only
// symptom was a 503 with a null body and no error text anywhere.
//
// ⚠ SMTP_PORT MUST be 465. `tls` is derived from the port, so 587 opens a
// PLAINTEXT socket to a STARTTLS port, denomailer hangs, and the edge isolate is
// killed. See docs/wiki/pages/lessons/smtp-port-must-be-465.md.

import { resolveSender, type SenderKey } from './sender-profiles.ts'

export type EmailStatus = 'sent' | 'skipped' | 'failed'

export interface EmailResult {
  status: EmailStatus
  /** The real SMTP error. Never swallowed — this is the whole point. */
  error?: string
  /** Which profile was used. */
  sender?: SenderKey
  /** True when the profile borrowed the default mailbox (no own credentials yet). */
  usedFallback?: boolean
  /** The From header actually sent, for log correlation. Contains no secret. */
  from?: string
  ms?: number
}

export interface SendEmailInput {
  /** Which identity this email comes from. */
  sender: SenderKey
  to: string | string[]
  subject: string
  /** Plain-text body. Falls back to `subject` when absent. */
  text?: string
  html?: string
  /** Override the profile's Reply-To (rare — e.g. route to a specific clinician). */
  replyTo?: string
}

/**
 * Send one email as `sender`.
 *
 * Returns `skipped` when SMTP is not configured (never throws — a missing
 * secret must not break the caller's real work, e.g. an account deletion that
 * has already happened). Returns `failed` WITH the provider's error string
 * when the send is genuinely rejected.
 */
export async function sendEmail(
  input: SendEmailInput,
  // Wrapped, not passed as `Deno.env.get` — an unbound method loses `this`.
  // The parameter exists so tests can inject a fake environment.
  env: (name: string) => string | undefined = (n) => Deno.env.get(n),
): Promise<EmailResult> {
  const recipients = (Array.isArray(input.to) ? input.to : [input.to])
    .map((r) => r.trim())
    .filter(Boolean)
  if (recipients.length === 0) return { status: 'skipped', error: 'no recipient' }

  const resolved = resolveSender(input.sender, env)
  if (!resolved.ok) return { status: 'skipped', error: resolved.detail, sender: input.sender }

  const { creds } = resolved
  const started = Date.now()
  // deno-lint-ignore no-explicit-any
  let client: any = null
  try {
    const { SMTPClient } = await import('https://deno.land/x/denomailer@1.6.0/mod.ts')
    client = new SMTPClient({
      connection: {
        hostname: creds.host,
        port: creds.port,
        tls: creds.tls,
        auth: { username: creds.username, password: creds.password },
      },
    })
    await client.send({
      from: creds.from,
      to: recipients,
      replyTo: input.replyTo ?? creds.replyTo,
      subject: input.subject,
      content: input.text ?? input.subject,
      html: input.html,
    })
    return {
      status: 'sent',
      sender: input.sender,
      usedFallback: creds.usedFallback,
      from: creds.from,
      ms: Date.now() - started,
    }
  } catch (e) {
    return {
      status: 'failed',
      error: e instanceof Error ? e.message : String(e),
      sender: input.sender,
      usedFallback: creds.usedFallback,
      from: creds.from,
      ms: Date.now() - started,
    }
  } finally {
    // close() returns void in some denomailer versions — await handles both, and
    // the guard means a close failure can never mask the result above.
    try {
      if (client && typeof client.close === 'function') await client.close()
    } catch { /* ignore */ }
  }
}
