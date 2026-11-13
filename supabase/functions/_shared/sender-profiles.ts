// supabase/functions/_shared/sender-profiles.ts
//
// WHO an email appears to come from. Pure data + resolution — deliberately ZERO
// imports, so the Deno edge runtime and vitest can both load this exact file
// (no inline-copy, no drift). The actual sending lives in ./email.ts.
//
// ── The rule that shapes all of this ────────────────────────────────────────
// Infomaniak rejects a From address that is not the authenticated mailbox:
//   550: 5.7.1 Sender mismatch
// Verified live 2026-07-27 — `alex@`, `data@` and `legal@` were ALL refused while
// authenticated as `thomas@`. Aliases do not help. Only the DISPLAY NAME in front
// of the address is free text.
//
// So a profile sends from its own address ONLY if it has its own credentials.
// Otherwise it falls back to the default mailbox, keeping its display name and
// Reply-To — which still shows the right person and still routes replies
// correctly. Adding `SMTP_USER_ALEX`/`SMTP_PASS_ALEX` later upgrades that profile
// to a genuine From with NO code change.

export type SenderKey = 'thomas' | 'alex' | 'system'

export interface SenderProfile {
  key: SenderKey
  /** Name the recipient sees in their inbox. */
  displayName: string
  /** Mailbox this profile sends AS — only used when its own credentials exist. */
  address: string
  /** Env var holding this profile's SMTP username. */
  userEnv: string
  /** Env var holding this profile's SMTP app password. */
  passEnv: string
  /** Where replies go. The shared business inbox for anything patient-facing. */
  replyTo: string
  /** Why this profile exists — for humans picking one. */
  useFor: string
}

/** Shared business inbox — clients' replies land here, never in a personal mailbox. */
export const SUPPORT_INBOX = 'support@functionalps.ch'

export const SENDER_PROFILES: Record<SenderKey, SenderProfile> = {
  thomas: {
    key: 'thomas',
    displayName: 'Thomas · FunctionAlps',
    address: 'thomas@functionalps.ch',
    userEnv: 'SMTP_USER_THOMAS',
    passEnv: 'SMTP_PASS_THOMAS',
    replyTo: SUPPORT_INBOX,
    useFor: 'Business: invoices, billing, account and legal notices.',
  },
  alex: {
    key: 'alex',
    displayName: 'Alex · FunctionAlps',
    address: 'alex@functionalps.ch',
    userEnv: 'SMTP_USER_ALEX',
    passEnv: 'SMTP_PASS_ALEX',
    replyTo: SUPPORT_INBOX,
    useFor: 'Clinical: check-in reminders, appointments, care-plan changes.',
  },
  system: {
    key: 'system',
    displayName: 'FunctionAlps',
    address: 'noreply@functionalps.ch',
    userEnv: 'SMTP_USER_SYSTEM',
    passEnv: 'SMTP_PASS_SYSTEM',
    replyTo: SUPPORT_INBOX,
    useFor: 'Automated notices with no personal author, and internal team alerts.',
  },
}

export interface SmtpCredentials {
  host: string
  port: number
  /** Implicit TLS. Infomaniak: 465 = TLS on. 587 would need STARTTLS, which the client does NOT do. */
  tls: boolean
  username: string
  password: string
  /** Full From header value, e.g. `Alex · FunctionAlps <alex@functionalps.ch>`. */
  from: string
  replyTo: string
  /**
   * True when this profile had no credentials of its own and borrowed the default
   * mailbox. The display name and Reply-To are still the profile's; only the
   * underlying address differs.
   */
  usedFallback: boolean
}

export type SenderResolution =
  | { ok: true; creds: SmtpCredentials }
  | { ok: false; reason: 'unknown-profile' | 'no-default-smtp'; detail: string }

/** Read an env var, treating blank/whitespace as absent. */
function read(env: (n: string) => string | undefined, name: string): string | null {
  const v = env(name)
  if (typeof v !== 'string') return null
  const t = v.trim()
  return t.length > 0 ? t : null
}

/**
 * Build an RFC-5322 From header. A display name containing a comma, quote,
 * angle bracket, colon or semicolon MUST be quoted or the header is malformed
 * and the message is rejected.
 */
export function formatAddress(displayName: string, address: string): string {
  const name = displayName.trim()
  if (!name) return address
  if (/["\\,;:<>@[\]]/.test(name)) {
    return `"${name.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}" <${address}>`
  }
  return `${name} <${address}>`
}

/** Extract the bare address from a From header value, or return it unchanged. */
export function bareAddress(from: string): string {
  const m = from.match(/<([^>]+)>/)
  return (m ? m[1] : from).trim()
}

/**
 * Resolve the credentials + headers for a sender profile.
 *
 * Order:
 *   1. The profile's OWN credentials → a genuine `From: its own address`.
 *   2. Otherwise the default `SMTP_USER`/`SMTP_PASS` → the profile's display name
 *      and Reply-To over the DEFAULT address (`usedFallback: true`).
 *
 * `host`/`port` are shared across profiles — one provider.
 */
export function resolveSender(
  key: SenderKey,
  env: (name: string) => string | undefined,
): SenderResolution {
  const profile = SENDER_PROFILES[key]
  if (!profile) {
    return { ok: false, reason: 'unknown-profile', detail: `no sender profile named "${key}"` }
  }

  const host = read(env, 'SMTP_HOST')
  const port = Number(read(env, 'SMTP_PORT') ?? '465')
  if (!host) {
    return { ok: false, reason: 'no-default-smtp', detail: 'SMTP_HOST is not set' }
  }

  const ownUser = read(env, profile.userEnv)
  const ownPass = read(env, profile.passEnv)
  if (ownUser && ownPass) {
    return {
      ok: true,
      creds: {
        host,
        port,
        tls: port === 465,
        username: ownUser,
        password: ownPass,
        // Authenticated as this mailbox, so From may legitimately be its address.
        from: formatAddress(profile.displayName, ownUser),
        replyTo: profile.replyTo,
        usedFallback: false,
      },
    }
  }

  const defUser = read(env, 'SMTP_USER')
  const defPass = read(env, 'SMTP_PASS')
  if (!defUser || !defPass) {
    return {
      ok: false,
      reason: 'no-default-smtp',
      detail: `profile "${key}" has no ${profile.userEnv}/${profile.passEnv}, and SMTP_USER/SMTP_PASS are not set either`,
    }
  }

  // Fallback: borrow the default mailbox. The address MUST be the authenticated
  // one (550 Sender mismatch otherwise) — but the name and Reply-To stay the
  // profile's, so the recipient still sees the right person and replies still land
  // in the right inbox.
  const defAddress = bareAddress(read(env, 'SMTP_FROM') ?? defUser)
  return {
    ok: true,
    creds: {
      host,
      port,
      tls: port === 465,
      username: defUser,
      password: defPass,
      from: formatAddress(profile.displayName, defAddress),
      replyTo: profile.replyTo,
      usedFallback: true,
    },
  }
}
