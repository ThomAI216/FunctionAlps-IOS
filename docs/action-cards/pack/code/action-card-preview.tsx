'use client'

// components/action-cards/action-card-preview.tsx
// The card exactly as the iOS app draws it — same wall (Sand 1), same glass (white
// frost 60 % + blur), same type (DM Serif Display / DM Sans), same layout as
// ActionCardView.swift: the row in "Today's actions", then the page it opens.
// Display derives from props; local state is only the preview's own toggles.

import * as React from 'react'
import { cardSteps, youtubeSearchUrl } from '@/lib/action-cards/logic'
import { CARD_KIND_LABEL, type ActionCardDraft, type CardKind, type LibraryArticleOption } from '@/lib/action-cards/types'

type Lang = 'en' | 'fr'
type Face = 'easy' | 'standard' | 'progression'

const INK = '#1A1A16'
const STONE = '#7A796F'
const FOREST = '#2E5438'
const FOREST_SOFT = '#4A8A5C'

const KIND_FR: Record<CardKind, string> = {
  breath: 'Respiration',
  movement: 'Mouvement',
  routine: 'Routine',
  nutrition: 'Nutrition',
  mind: 'Esprit',
  learn: 'Comprendre',
}

const SLOT_LABEL: Record<Lang, Record<string, string>> = {
  en: { morning: 'Morning', midday: 'Midday', evening: 'Evening', anytime: 'Anytime' },
  fr: { morning: 'Matin', midday: 'Midi', evening: 'Soir', anytime: "N'importe quand" },
}

const T = {
  en: {
    today: "Today's actions",
    version: "Today's version",
    easy: 'Gentle',
    standard: 'Standard',
    progression: 'Further',
    how: 'How to do it',
    why: 'Why it is in your plan',
    watch: 'Watch the demonstration',
    youtube: (q: string) => `Or search “${q}” on YouTube ↗`,
    read: 'Read in the library',
    done: 'Done',
    notToday: 'Not today',
    start: 'Start',
    breathe: 'Breathe with the circle',
    back: '‹ Today',
  },
  fr: {
    today: 'Actions du jour',
    version: "Aujourd'hui, la version",
    easy: 'Douce',
    standard: 'Normale',
    progression: 'Plus loin',
    how: 'Comment faire',
    why: 'Pourquoi dans votre plan',
    watch: 'Regarder la démonstration',
    youtube: (q: string) => `Ou chercher « ${q} » sur YouTube ↗`,
    read: 'À lire dans la bibliothèque',
    done: "C'est fait",
    notToday: "Pas aujourd'hui",
    start: 'Commencer',
    breathe: 'Respirez avec le cercle',
    back: '‹ Aujourd’hui',
  },
} as const

const glass: React.CSSProperties = {
  background: 'rgba(255,255,255,0.60)',
  border: '1px solid rgba(255,255,255,0.72)',
  borderRadius: 22,
  boxShadow: '0 8px 24px rgba(0,0,0,0.10)',
  backdropFilter: 'blur(18px)',
  WebkitBackdropFilter: 'blur(18px)',
}

/** The language's text, falling back to the other one — what the app does when a French field is empty. */
function pick(d: ActionCardDraft, lang: Lang, en: keyof ActionCardDraft, fr: keyof ActionCardDraft): string {
  const a = String(d[lang === 'fr' ? fr : en] ?? '').trim()
  return a || String(d[lang === 'fr' ? en : fr] ?? '').trim()
}

export function ActionCardPreview({
  draft,
  articles,
}: {
  draft: ActionCardDraft
  articles: LibraryArticleOption[]
}) {
  const [lang, setLang] = React.useState<Lang>('fr')
  const [face, setFace] = React.useState<Face>('standard')
  const t = T[lang]

  const hasEasy = Boolean(pick(draft, lang, 'easy_title', 'easy_title_fr'))
  const hasRev = Boolean(pick(draft, lang, 'rev_title', 'rev_title_fr'))
  const shownFace: Face = face === 'easy' && !hasEasy ? 'standard' : face === 'progression' && !hasRev ? 'standard' : face

  const baseTitle = pick(draft, lang, 'title', 'title_fr') || (lang === 'fr' ? 'Titre de la carte' : 'Card title')
  const title =
    shownFace === 'easy' ? pick(draft, lang, 'easy_title', 'easy_title_fr') : shownFace === 'progression' ? pick(draft, lang, 'rev_title', 'rev_title_fr') : baseTitle
  const description =
    shownFace === 'easy'
      ? pick(draft, lang, 'easy_description', 'easy_description_fr')
      : shownFace === 'progression'
        ? pick(draft, lang, 'rev_description', 'rev_description_fr')
        : pick(draft, lang, 'description', 'description_fr')
  const steps = cardSteps(pick(draft, lang, 'how_md', 'how_md_fr'))
  const why = pick(draft, lang, 'general_why', 'general_why_fr')
  const kindLabel = draft.card_kind ? (lang === 'fr' ? KIND_FR[draft.card_kind] : CARD_KIND_LABEL[draft.card_kind]) : null
  const meta = [SLOT_LABEL[lang][draft.default_slot ?? 'anytime'], draft.duration_min ? `${draft.duration_min} min` : null].filter(Boolean).join(' · ')
  const article = articles.find((a) => a.slug === draft.article_slug)

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs text-muted-foreground">As members see it on iPhone</p>
        <div className="flex gap-1 rounded-md border p-0.5 text-xs">
          {(['fr', 'en'] as const).map((l) => (
            <button
              key={l}
              type="button"
              onClick={() => setLang(l)}
              className={`rounded px-2 py-0.5 ${lang === l ? 'bg-foreground text-background' : 'text-muted-foreground'}`}
            >
              {l.toUpperCase()}
            </button>
          ))}
        </div>
      </div>

      <div
        className="mx-auto overflow-hidden"
        style={{
          width: 390,
          maxWidth: '100%',
          borderRadius: 44,
          border: '10px solid #111',
          backgroundColor: '#d9c7b0',
          backgroundImage: "url('/action-cards/wall-sand-1.jpg')",
          backgroundSize: 'cover',
          backgroundPosition: 'center top',
          fontFamily: "'DM Sans', system-ui, sans-serif",
          color: INK,
        }}
      >
        <div style={{ height: 720, overflowY: 'auto', padding: '44px 16px 28px' }}>
          {/* The row in "Today's actions" on Home */}
          <div style={{ ...glass, padding: 16, marginBottom: 14 }}>
            <div style={{ fontSize: 17, fontWeight: 600, marginBottom: 10 }}>{t.today}</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div
                aria-hidden
                style={{ width: 26, height: 26, borderRadius: 13, border: `2px solid ${FOREST_SOFT}`, flex: '0 0 auto' }}
              />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 600 }}>{baseTitle}</div>
                <div style={{ fontSize: 12, color: STONE }}>{[kindLabel, meta].filter(Boolean).join(' · ')}</div>
              </div>
              <div style={{ color: STONE, fontSize: 14 }}>›</div>
            </div>
          </div>

          {/* The page it opens */}
          <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 10, display: 'inline-block', ...glass, borderRadius: 14, padding: '6px 12px' }}>
            {t.back}
          </div>

          <div style={{ ...glass, overflow: 'hidden', marginBottom: 12 }}>
            {draft.image_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={draft.image_url} alt={draft.image_alt || ''} style={{ width: '100%', height: 170, objectFit: 'cover', display: 'block' }} />
            ) : null}
            <div style={{ padding: 16 }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.09em', textTransform: 'uppercase', color: '#4B4A42' }}>
                {[kindLabel, meta].filter(Boolean).join(' · ') || '—'}
              </div>
              <div style={{ fontFamily: "'DM Serif Display', Georgia, serif", fontSize: 26, lineHeight: 1.15, marginTop: 6 }}>{title || baseTitle}</div>
              {description ? <p style={{ fontSize: 14, lineHeight: 1.45, marginTop: 8, color: '#3d3c36' }}>{description}</p> : null}
            </div>
          </div>

          {draft.card_kind === 'breath' ? (
            <div style={{ ...glass, padding: 18, marginBottom: 12, textAlign: 'center' }}>
              <div
                aria-hidden
                style={{
                  width: 132,
                  height: 132,
                  margin: '4px auto 12px',
                  borderRadius: '50%',
                  background: 'radial-gradient(circle, rgba(74,138,92,0.35), rgba(74,138,92,0.12))',
                  border: `2px solid ${FOREST_SOFT}`,
                  animation: 'fa-breathe 8s ease-in-out infinite',
                }}
              />
              <div style={{ fontSize: 13, color: STONE }}>{t.breathe}</div>
              <div style={{ marginTop: 10, minHeight: 44, borderRadius: 22, background: FOREST, color: '#fff', fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                {t.start}
                {draft.duration_min ? ` · ${draft.duration_min} min` : ''}
              </div>
              <style>{'@keyframes fa-breathe{0%,100%{transform:scale(.78)}50%{transform:scale(1)}}'}</style>
            </div>
          ) : null}

          {(hasEasy || hasRev) && (
            <div style={{ ...glass, padding: 14, marginBottom: 12 }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.09em', textTransform: 'uppercase', color: '#4B4A42', marginBottom: 8 }}>
                {t.version}
              </div>
              <div style={{ display: 'flex', gap: 6 }}>
                {(['easy', 'standard', 'progression'] as const)
                  .filter((f) => (f === 'easy' ? hasEasy : f === 'progression' ? hasRev : true))
                  .map((f) => (
                    <button
                      key={f}
                      type="button"
                      onClick={() => setFace(f)}
                      style={{
                        flex: 1,
                        minHeight: 38,
                        border: 0,
                        borderRadius: 12,
                        fontSize: 13,
                        fontWeight: 600,
                        cursor: 'pointer',
                        background: shownFace === f ? FOREST : 'rgba(255,255,255,0.7)',
                        color: shownFace === f ? '#fff' : INK,
                      }}
                    >
                      {t[f]}
                    </button>
                  ))}
              </div>
            </div>
          )}

          {draft.video_url || draft.youtube_query ? (
            <div style={{ ...glass, padding: 14, marginBottom: 12 }}>
              {draft.video_url ? (
                <a href={draft.video_url} target="_blank" rel="noreferrer" style={{ display: 'block', borderRadius: 14, overflow: 'hidden', background: '#1A1A16', color: '#fff', height: 150, position: 'relative' }}>
                  <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 34 }}>▶</span>
                  <span style={{ position: 'absolute', left: 12, bottom: 10, fontSize: 12, opacity: 0.9 }}>{draft.video_title || t.watch}</span>
                </a>
              ) : null}
              {draft.youtube_query ? (
                <a href={youtubeSearchUrl(draft.youtube_query)} target="_blank" rel="noreferrer" style={{ display: 'block', marginTop: draft.video_url ? 10 : 0, fontSize: 13, fontWeight: 600, color: FOREST }}>
                  {t.youtube(draft.youtube_query)}
                </a>
              ) : null}
            </div>
          ) : null}

          {steps.length > 0 && (
            <div style={{ ...glass, padding: 16, marginBottom: 12 }}>
              <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 10 }}>{t.how}</div>
              <ol style={{ listStyle: 'none', padding: 0, margin: 0, display: 'grid', gap: 10 }}>
                {steps.map((s, i) => (
                  <li key={i} style={{ display: 'flex', gap: 10, fontSize: 14, lineHeight: 1.4 }}>
                    <span style={{ flex: '0 0 22px', height: 22, borderRadius: 11, background: 'rgba(74,138,92,0.16)', color: FOREST, fontSize: 12, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      {i + 1}
                    </span>
                    <span>{s}</span>
                  </li>
                ))}
              </ol>
            </div>
          )}

          {why ? (
            <div style={{ ...glass, padding: 16, marginBottom: 12 }}>
              <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 6 }}>{t.why}</div>
              <p style={{ fontSize: 14, lineHeight: 1.45, color: '#3d3c36', margin: 0 }}>{why}</p>
            </div>
          ) : null}

          {article ? (
            <div style={{ ...glass, padding: 14, marginBottom: 12, display: 'flex', alignItems: 'center', gap: 12 }}>
              <div aria-hidden style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(74,138,92,0.18)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: FOREST, fontSize: 18 }}>
                ✎
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 11, color: STONE }}>{t.read}</div>
                <div style={{ fontSize: 14, fontWeight: 600 }}>{article.title}</div>
              </div>
              <div style={{ color: STONE }}>›</div>
            </div>
          ) : null}

          <div style={{ display: 'grid', gap: 8, marginTop: 6 }}>
            <div style={{ minHeight: 50, borderRadius: 25, background: FOREST, color: '#fff', fontSize: 16, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{t.done}</div>
            <div style={{ minHeight: 46, borderRadius: 23, background: 'rgba(255,255,255,0.6)', border: '1.5px solid rgba(26,26,22,0.2)', fontSize: 15, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {t.notToday}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
