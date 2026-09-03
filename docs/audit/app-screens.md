# Audit — Patient App screens / navigation / gating / theme / i18n (raw)

Source repo: `FunctionAlps-APP` (`/home/user/functionalps-app`, commit ad44f35, cloned 2026-09-02). Expo ~54 + expo-router (RN 0.81 + react-native-web), 97 files under `app/`. Produced by a read-only exploration agent; kept verbatim as the evidence base for `APP_MAP.md` and the design system.

## 0. Sources read first
- `CLAUDE.md`, `docs/wiki/index.md` (states: the ONE live library is the `(tabs)/library` members-plane path; STUDIO `kb_nodes`/`library-content` path is PARKED; AI chat is DARK)

## 1. Root providers & gating

### `app/_layout.tsx` (530 lines) — the whole gate stack
Provider order (outermost first): `GestureHandlerRootView` → `SafeAreaProvider` → `QueryClientProvider` (TanStack Query, `staleTime` 5 min, `retry: 2`) → `StatusBar style="dark"` → `WebMobileFrame` → `AuthGate` → `<Slot/>` + `<HelpLayer/>` + `<LanguageOfferSheet/>`.

- **Fonts** (`useFonts`, returns `null` until loaded — the de-facto splash hold): `DMSerifDisplay_400Regular`, `DMSans_400Regular/500Medium/600SemiBold/700Bold`, from `@expo-google-fonts/*`. **No font files in `assets/`**.
- **Splash**: `app.json` only (`./assets/splash-icon.png`, bg `#0D9488`). A second neutral hold `#f8fafc` while the first profile read is in flight.
- **`DEV_BYPASS_AUTH = false`** (hardcoded, line 46).

**Gate order in `AuthGate`:**
1. Neutral splash while first profile read pending.
2. **Language** — `FR_UI_ENABLED && !localeChosen && !session` → `<LanguageChoiceScreen/>`. With a session: non-blocking `<LanguageOfferSheet/>`.
3. **Access window** — `useAppAccess(patientId)`, `!access.allowed` → `<AccessWindowGate/>`. Fails OPEN on unknowns.
4. **Onboarding (members target only)** — never renders on the default `'app'` target.
5. **Consent** — `CONSENT_GATE_ENABLED && consentStatus === 'required'` → `<ConsentGate/>` (age 18+ step, 2 required ticks, 2 notices, hashed per-locale definitions in CM OS).
6. Else `<Slot/>` + `<HelpLayer/>`.
- The **first-run AI consent gate is REMOVED** (2026-08-20).

**Routing effect (auth → onboarding → tabs), lines 210–272:**
- No session → remember `segments.join('/')` in a module-level `pendingRoute` → `router.replace('/(auth)/login')`.
- Session + `user_metadata.onboarding_complete !== true` + `dbOnboardingStatus === 'unknown'` → wait (no flash).
- `needs_onboarding` → `router.replace(resumeRoute(onboardingStore.nutritionOnboardingStep))`.
- `inAuth` → replace to `pendingRoute ?? '/(tabs)'`.
- Anything not in `(onboarding)|(tabs)|(screens)` → `/(tabs)`.

**Onboarding decision rule** — `lib/onboarding/gate.ts::resolveOnboardingStatus`: `done` iff `onboarding_completed_at` is set **AND** all five energy inputs (`app_sex`, `app_age`, `app_height_cm`, `app_weight_kg`, `activity_level`) are on `nb_patient_app_profiles`. Read failure fails **open**.

**Feature flags:**
| Flag | File | Default |
|---|---|---|
| `ONBOARDING_GATE_ENABLED` | `app/_layout.tsx:57` | ON |
| `ONBOARDING_TARGET` | `app/_layout.tsx:64` | `'app'` |
| `CONSENT_GATE_ENABLED` | `lib/legal/consents.ts:43` | ON |
| `FR_UI_ENABLED` | `lib/i18n/feature-flag.ts` | ON |
| `AI_CHAT_ENABLED` | `lib/config/ai-chat-flag.ts` | **OFF** |
| `HABITS_UI_ENABLED` | `lib/plan/feature-flag.ts` | **hardcoded `false`** |
| `COVERAGE_NUDGE_ENABLED` | `lib/meal-log/coverage-flag.ts` | **OFF** |

**Also in AuthGate:** `ensurePatientId(session)` on session establish + retry on `AppState` focus; `useLogStore.loadMeals`; `getPatientProfile(pid)` hydrates `useOnboardingStore` (sex/age/height/weight/activity/goals/complaints/diet/supplements/body-fat/goal mode/sport/meals+snacks/custom macros/DB macro targets); `checkPendingPostMealCheckin`; `useSyncLocaleToProfile` (called twice — redundant).

**Deep-link scheme**: `app.json` `"scheme": "functionalps"`. No `expo-linking` import; `Linking.openURL` outbound only.

### `app/(auth)/_layout.tsx` — `<Stack headerShown:false, animation:'fade'>`, one screen: `login`.
### `app/(onboarding)/_layout.tsx` — `slide_from_right`, bg `#f8fafc`, `gestureEnabled:false`.
### `app/(screens)/_layout.tsx` — `<Stack>` + `<FloatingNavBar/>` overlay, hidden on: `/checkin-hub`, `/daily-checkin`, `/checkin-moment`, `/gut-intelligence-checkin`, `/capture/camera`, `/capture/analyzing`, `/profile-messages`, `/library/read`.
### `app/+html.tsx` — dead in the SPA build.

## 2. Route census

### `(auth)` — 1 route
| route | purpose | store/hook | key actions | navigates to |
|---|---|---|---|---|
| `/(auth)/login` | Email-first auth mirroring the members dashboard (mito bg, FA logo, alpine-glass card, Google OR email → exists? sign-in / create account, forgot-password, live password checklist) | `supabase.auth` direct; `useT`, `toMemberMessage` | sign in, sign up, Google, reset password | `/(screens)/legal/terms`, `/(screens)/legal/privacy` |

### `(onboarding)` — two distinct flows

**A. `ob-*` — the LIVE mandatory onboarding** (8 steps; `lib/onboarding/steps.ts`, `ONBOARDING_VERSION = 'nutrition_onboarding_v1'`). Order: welcome → baseline → activity → energy → nutrition → meals → checkins → ready.

| route | purpose | store/hook | key actions | navigates to |
|---|---|---|---|---|
| `ob-welcome` | why we ask; decides whether the baseline is asked at all | `useAuthStore`, `useKnownBaseline` | Continue | next step, `?known=1` if baseline on file |
| `ob-baseline` | age, sex, height, weight | `useOnboardingStore`, `useBaselinePrefill`, `saveBaseline` | fill form, Continue | `ob-activity` |
| `ob-activity` | Activity-level cards | `useOnboardingStore`, `saveBaseline`, `track()` | pick activity | `ob-energy` |
| `ob-energy` | the energy compass — the only calorie number; PRD §21 forbids "limit"/"remaining"/rings | `useOnboardingStore`, `macroColors` | Continue | `ob-nutrition` |
| `ob-nutrition` | why the number is not the point | `useOnboardingStep` | Continue | `ob-meals` |
| `ob-meals` | photograph-the-plate, 5-step strip + AI-imperfection note | `useOnboardingStep` | Continue | `ob-checkins` |
| `ob-checkins` | what a check-in is, cadence, post-meal reactions | `useOnboardingStep` | Continue | `ob-ready` |
| `ob-ready` | **stamps `onboarding_completed_at` on OPEN**, then `requestOnboardingRecheck()` | `stampOnboardingComplete`, `useMealPhotoCapture` | scan a meal / check in / go home | `checkin-moment` or `/(tabs)` |

**B. `q1-*` — the OPTIONAL Day-1 assessment of the 5-day program** (reached from `/(screens)/program`).

| route | purpose | key actions | navigates to |
|---|---|---|---|
| `q1-profile` | Sex + age + basics | Continue | `q1-complaints` |
| `q1-complaints` | body-system complaints (`SYSTEMS`) | multi-select | `q1-going-deeper` |
| `q1-going-deeper` | per-system symptom frequency | 4-point frequency | `q1-probes` |
| `q1-probes` | probe questions | answer | `q1-objectives` |
| `q1-objectives` | objectives | multi-select | `q1-report` |
| `q1-report` | "Functional Snapshot": templated narrative + 8-spoke `FunctionalRadar`; calls `submitQ1` → edge fn `q1-complete` | submit | `/(tabs)` |
| `welcome` | **DEAD/LEGACY** entry to the q1 flow | — | `q1-profile` |

### `(tabs)` — 6 routes (5 visible)
| route | purpose | store/hook | key actions | navigates to |
|---|---|---|---|---|
| `/(tabs)/index` (Home) | Overall functional trend card, protocol review, two square action tiles (scan / check-in), plan card (flagged off), latest article, messages | `useDailyStore`, `useLogStore`, `useOnboardingStore`, `useAuthStore`, `useWearableHistory`, `useMealPhotoCapture`, `loadCheckinHistory`, `loadTodayCheckin`, `shouldPromptCheckin` | open photo capture, check in, evening modal | `/(tabs)/health`, `checkin-moment` |
| `/(tabs)/health` (Trends) | `FunctionalScoreCrown` + `GutIntelligenceCard` + `MeasuredVsFeltCard` + `DailyCheckinCTA` | `useDailyStore`, `useLogStore`, `useScoreTips`, `useWearableHistory`, `deriveTrends`, `measuredVsFelt` | open pillar, open gut | `pillar/[key]`, `gut-intelligence`, `daily-checkin` |
| `/(tabs)/log` (Food) | Meal log: macros-today card, photo-scan hero, favorites strip, describe-a-meal, today's meals with swipe-delete + relog | `useLogStore`, `useFavoritesStore`, `useMealPhotoCapture` | scan, describe, relog, undo, delete, meal reaction | `meal-detail/[id]`, `capture/*` |
| `/(tabs)/library` | **THE live library** — members plane (`library_tracks`/`library_track_lessons`/`member_library_access`): plan header, chip rail, Priority for you, Continue, Tracks, Foundations, Supplements | `loadLibraryBundle`, `DEMO_TRACKS/DEMO_RESOURCES` fallback | open track, open lesson | `library/track/[slug]`, `library/read/[slug]` |
| `/(tabs)/profile` | Identity header, functional-trend preview, care plan, complaints, edit baseline, feedback, guide | `useAuthStore`, `useOnboardingStore`, `useCarePlan`, `AccessWindowStrip` | open settings/care plan/guide/feedback, edit baseline | `profile-settings`, `dashboard`, `profile-care-plan`, `profile-feedback`, `guide`, `ob-baseline?edit=1` |
| `/(tabs)/chat` | NutriBot — **HIDDEN tab (`href: null`) and DARK** | `useChatStore`, … | (gated) | `capture/analyzing` |

### `(screens)` by cluster

**Capture / meal (5)**: `capture/camera` (expo-image-picker, not expo-camera) → `capture/analyzing` (`ColorCycleLogo`, async status polling, portion review) → `capture/confirm` (~700 lines: edit items, reprice, re-analyze, coverage prompt, protocol flags, learned-alias toast, scores row) → `/(tabs)`; `capture/day-review` (orphan); `meal-detail/[id]` (photo, macros, `ScoreRing`s, flags, patient note, reaction line).

**Check-ins (5)**: `checkin-hub` (today's moments strip, functional + gut trend cards); `checkin-moment` (**the current check-in** — morning/midday/evening via `?slot=`; dimension cards + pill groups + custom pills; fires the daily report); `daily-checkin` (older full functional check-in, still linked); `gut-intelligence-checkin` (gut dimensions, Bristol stool inputs, meal reactions); `gut-intelligence` (gut score read-out).

**Health / scores / pillars (10)**: `scores` (hub), `score/[key]`, `score-explainer/[score]`, `pillar/[key]` → `PillarDetailScreen`, `dashboard` (legacy Trends, still linked from Profile), `health-{energy,inflammation,mood,sleep,stress}` (wrappers around `HealthMetricScreen`), `biomarkers/[system]` + `biomarkers/[markerId]` (**mock, dead**).

**Program / plan / habits (10)**: `program` (5-day pre-call stepper), `nutrition-setup` (Day 2), `movement-setup`/`movement-report` (Day 3), `sleep-setup`/`sleep-report` (Day 4), `mind-setup`/`mind-report` (Day 5 + "Book your call"), `plan` / `plan-add` / `plan-habit` (Habit Loop v2 — **`HABITS_UI_ENABLED === false` → redirect to `/(tabs)`**).

**Reports (3+1)**: `report/index` (calendar + daily/weekly/monthly cards), `report/[period]` (renderer; PDF + JSON export), `functional-activation` (orphan).

**Library / resources / guides (6)**: `library/track/[slug]`, `library/read/[slug]` (**the reader** — warm-paper wall, serif headings, own mark-done bar; `body_md` via `member_library_get`, custom markdown parser), `guide/index` + `guide/[key]` (from `lib/help/help-content.ts`), `your-resources` + `resource/[id]` (**PARKED**).

**Nutrition / macros / micronutrients (7)**: `nutrition-macros` (macro settings), `macros-details`, `micronutrients`, `micro-group/[key]`, `micro-nutrient/[key]`, `diet-detail/[slug]` (orphan), `nutrition-ai` (**DARK**).

**Profile / settings / privacy / legal (14)**: `profile-settings` (appearance walls, **language picker**, privacy, messages, help, wearables, sign out via `clearUserScopedStores`), `profile-privacy` (export data, delete account sheet, legal docs, consents), `privacy-consents`, `privacy-view-data`, `legal/{terms,privacy,legal-notice}`, `profile-messages` (clinician thread), `profile-care-plan`, `profile-help`, `profile-feedback`, `profile-notifications` (orphan), `profile-wearables` (Thryve connect/disconnect), `profile-supplements` / `profile-tests` / `profile-appointment` (orphans), `profile-nutrition` (redirect stub).

**Misc / dead / dev-only**: `shader-demo` (dev GLSL), `supplements/index` (mock), `symptoms/log` (mock), `log-supplements` (orphan), `weekly-theme` (orphan).

**Orphan count: 15 route files with zero inbound references** — `biomarkers/[system]`, `biomarkers/[markerId]`, `capture/day-review`, `diet-detail/[slug]`, `functional-activation`, `log-supplements`, `profile-appointment`, `profile-notifications`, `profile-supplements`, `profile-tests`, `shader-demo`, `supplements/index`, `symptoms/log`, `weekly-theme`, `(onboarding)/welcome`.

## 3. Tabs
`app/(tabs)/_layout.tsx`: **5 visible tabs**, `tabBarShowLabel: false` (labels drawn inside `TabIcon`, translated via `useT`):

| tab | label | lucide icon |
|---|---|---|
| `index` | Home | `Home` |
| `health` | Trends | `TrendingUp` |
| `log` | Food | `Salad` |
| `library` | Library | `BookOpen` |
| `profile` | Profile | `User` |

- Hidden tab: `chat` (`href: null`), gated dark.
- **Center FAB: none.** Scan lives as `MealScanCard` on Home and `PhotoScanCard` on Food.
- Bar: floating pill, `bottom: 30` (iOS) / `18`, `left/right: 16`, `height: 66`, `borderRadius: 33`, glass background (`BlurView intensity 48 tint light` + `rgba(255,255,255,0.38)`), border `rgba(255,255,255,0.55)`, shadow `#000 / 0.4 / r14 / y8`.
- Icon colours always dark: focused `#1A1A16`, unfocused `rgba(26,26,22,0.5)`; size 22; label 9.5px `DMSans_600SemiBold`.
- `lib/components/brand/FloatingNavBar.tsx` mirrors the bar for the `(screens)` stack.

## 4. Theme & design tokens
**Single source of truth: `lib/theme/tokens.ts`, mirrored into `tailwind.config.js`.**

### Brand colours
| name | hex |
|---|---|
| `forest` | `#2E5438` |
| `forestS` | `#4A8A5C` |
| `forestM` | `#C8D9CC` |
| `forestG` | `#EDF4EF` |
| `forestDark` | `#16301F` |
| `cream` | `#F5F0E8` |
| `cream2` | `#EDE8DE` |
| `warm` | `#FAF7F2` |
| `gold` | `#C48B35` |
| `goldS` | `#D4A84E` |
| `goldM` | `#F0E6D0` |
| `charcoal` | `#1A1A16` |
| `charcoal2` | `#14140F` |
| `ink2` | `#252521` |
| `stone` | `#7A796F` |
| `stoneLt` | `#A8A79E` |
| `white` | `#FFFFFF` |

**Macro palette (locked, `macroColors`)**: `kcal #2A3B34`, `protein #E0654F`, `carbs #E8A23D`, `fat #6C8AE4`. Nutrition-page pastels: protein `#E0A0A0`, carbs `#E6CF85`, fat `#A6C2E0`; labels `#C97B7B` / `#C2A24A` / `#7BA0C9`.
**Per-meal food scores (`scoreColors`)**: inflammation `#D98A2B`, glycemic `#3F7FC4`, digestion `#4A8A5C`.
**5-level functional scale (`scaleColors`)**: `#C0453A`, `#D98A2B`, `#D4A84E`, `#3F7FC4`, `#4A8A5C`.
**Legacy Tailwind-only sets**: `brand.50..900` (teal ramp `#f0fdfa`…`#134e4a`) and `score.{excellent #0d9488, good #059669, moderate #d97706, poor #dc2626}` — the teal `#0D9488` splash colour belongs to this legacy set.

### Radii & spacing
- `radii = { sm: 12, md: 16, lg: 22, xl: 24, pill: 200 }`.
- No custom spacing scale. `lib/theme/layout.ts::NAVBAR_CLEARANCE = 120`.

### Shadows
- `SURFACE_SHADOW` = `{ #000, offset {0,8}, opacity 0.22, radius 16, elevation 8 }`. Nav bar: `{ #000, 0.4, r14, y8 }`.

### Fonts
display `DMSerifDisplay_400Regular`; body `DMSans_400Regular`, `500Medium`, `600SemiBold`, `700Bold` — from npm packages `@expo-google-fonts/dm-sans` and `@expo-google-fonts/dm-serif-display` (OFL-licensed; the TTFs must be bundled for native).

### Assets present
`assets/`: `icon.png`, `adaptive-icon.png`, `favicon.png`, `splash-icon.png`, `help/plate-demo.jpg`, `images/report-mockup.webp`, `library/tracks/phase-1..6-*.webp`, `logos/fa-{blue,green,orange,purple,red,yellow}.webp` + `fa-logo-full.webp`, `textures/{blood-cells,digestion,dna-blue-portrait,dna-portrait,energy,fa-watermark,leaf-green,microbiome,mito-mobile,mood,sleep,stress}`, `wearables/{apple,decathlon,dexcom,fitbit,garmin,ihealth,komoot}.png`. `notification-icon.png` referenced by `app.json` is **missing**.

### Modes & the light-only setting
- `app.json` `"userInterfaceStyle": "light"`; `<StatusBar style="dark"/>`. No system-dark following.
- 5 palette modes (`lib/theme/palette.ts`): `light`, `dark`, `glass`, `dots`, `dots-dark`. User-facing choice is the **WALL** (`lib/theme/walls.ts`): 7 spotlight walls, default `dd9` **Sage** (`#E7F2E9→#BDDAC8`); others `dd7` Cream, `dd8` Honey, `dd10` Mist, `dd5` Forest (dark), `dd2` Alpine Night (dark), `dd6` Charcoal Gold (dark). Persisted per device (`fa-theme-wall`).
- `opaqueSurface(mode)` for prose (light → `warm #FAF7F2`; dark → `#252521`; dots-dark → `#1D3A26`; glass → `#17301F`).
- The in-app **gold accent is retired** → `palette.gold` resolves to `forestS` in light/dark; only the report PDF keeps real gold.

### Icon library
`lucide-react-native` ^1.7.0 everywhere; `react-native-svg` ^15 for custom glyphs.

### Styling stack note
NativeWind/Tailwind installed but screens are written with inline RN styles + theme tokens.

## 5. i18n
1. **UI strings: English-string-as-key.** `useT()` / `translate(en, locale, params)` (`lib/i18n/t.ts`). Catalog = `{ ...FR_UI_GENERATED, ...FR_UI }`: `fr-generated.ts` **~1,613 keys** (machine) + `fr.ts` **~367 keys** (hand overrides).
2. **Copy modules: dotted-path overlay** (`lib/i18n/overlay.ts`), consumed via `useCopy()`; 14 overlay files under `lib/data/fr/*`, `lib/help/fr/*`, `lib/meal-log/fr/*`, `lib/scores/fr/*`, `lib/legal/fr/*`.
3. `pickLocale<T>()` for whole typed twins.

**Languages:** exactly two — `LOCALES = ['en','fr']`, `DEFAULT_LOCALE = 'en'`. The consent catalog re-exports `Locale` so a third language can never be added without the consent gate.

**Selection:** `lib/i18n/store.ts` (zustand + persist `fa-locale`): `preference: 'auto'|'en'|'fr'` + `hasChosen`. `resolveAppLocale(pref)` → `'en'` if `!FR_UI_ENABLED` else `auto ? deviceLocale() : pref`. `deviceLocale()` reads `Intl.DateTimeFormat().resolvedOptions().locale`. **Legal pack is NOT flag-gated** and resolves from `deviceLocale()` so the recorded content hash matches what the member saw. `useSyncLocaleToProfile` writes `nb_patient_app_profiles.locale`. `speechLangFor(locale)` → `fr-CH` / `en-GB`. House-style guard: em/en dashes → ` · `.

## 6. Components worth mirroring natively
**Brand primitives (`lib/components/brand/`)**: `GlassCard` (liquid-glass card, universal container), `GlassButton`, `LiquidGlassFilter` (web), `AppBackground`/`SpotlightWall`, `DottedGlowBackground`, `DNABackground`, `ScoreRing` (0–100 ring), `MacroLine` (`480 kcal · P 24 · C 38 · F 26`), `FunctionalSlider` (0–100), `ReactionSlider`, `FunctionalScale` (5-level with FA marks red→green), `ColorCycleLogo` (loader), `MountainMark`, `FloatingNavBar`, `ThemeSwitcher`.
**Cards & tiles**: `lib/components/home/` `MealScanCard`, `CheckinPulseCard`, `LatestArticleCard`, `MessagesCard`, `PlanTodayCard`, `ProtocolReviewCard`, `Pop`; `components/health/trends/` `FunctionalScoreCrown`, `GutIntelligenceCard`, `MeasuredVsFeltCard`, `LongevityCard`, `CompoundScoreCard`, `HeroTrendCard`, `SignalCard`, `PillarDetailScreen`, `ScoreBarTrend` (14-day bars), `MiniMarkerTrend`, `FactorBar`, `GlassPanel`, `charts.tsx` (monotone cubic); `components/scores/` `ScoreCompass`, `ScoreHubTile`; `lib/components/library/TrackCard` family; `lib/components/nutrition/` `MacroBars`, `MacrosTodayCard`, `MealCard`, `Shimmer`; `components/nutrition/` `ActivityRings`, `MoleculeBadge`, `NumberWheel`, `SteppedSlider`, `MacroSliderCard`, `CalorieSummaryCard`, `ProfileSummaryCard`, `MealsSnacksCard`, `WheelPickerSheet`; `components/report/FunctionalRadar`; `components/reports/*`.
**Check-in**: `DimensionCard`, `PillGroup`, `RecoverySection`, `SleepDial` (dual-handle bed/wake dial), `SleepInputs`, `StoolInputs` (Bristol + frequency), `MealReactionsBlock`, `CheckinTrendCard`, `GutConclusionsCard`, `EveningCheckinModal`, `MealReactionModal`.
**Meal log**: `MealItemRows`, `MealItemsEditor`, `MealAdjustBar`, `MealScoresRow`, `ConfirmHero`, `NeedsInputCard`, `GramWheel`, `PreprocessItemList`, `PhotoPortionReview`, `CoveragePrompt`, `ProtocolWhySheet`, `PatientNote`, `MealReactionLine`, `LogMealCard`, `DescribeMealCard`, `PhotoScanCard`, `FavoritesStrip`, `SwipeableRow`.
**Bottom sheets**: `MealPhotoSheets`, `PhotoSourceSheet`, `PhotoGroupingSheet`, `ProtocolWhySheet`, `WheelPickerSheet`, `HelpSheet`, `DeleteAccountSheet`, `LanguageOfferSheet`.
**Toasts**: `UndoToast`, `RelogToast`, `LearnedToast`.
**Gates & legal**: `AccessWindowGate`, `AccessWindowStrip`, `OnboardingRequiredGate`, `ParkedSurfaceGate`, `ConsentGate`, `AgeGate`, `ConsentUpdateIntro`, `LegalDocument`, `MarkdownBody`.
**Help**: `HelpLayer`, `HelpSheet`, six animated demos; 13 help entries in `lib/help/help-content.ts`.
**Onboarding**: `OnboardingScaffold`, `ProgressBar`, `StepDots`. **Wearables**: `SourceCard`. **Plan**: `DayStateCard`, `StreakMark`.

## 7. Native capability usage
| capability | finding |
|---|---|
| Camera | `expo-camera` declared but **never imported**; `capture/camera.tsx` uses `expo-image-picker` in camera mode. |
| Photo library | `expo-image-picker` in `capture/camera`, `useMealPhotoCapture`, `analyze`/`photo-source`/`async-capture`, `PhotoSourceSheet`; screens: Home, Food, chat, `ob-ready`, `capture/*`, `meal-detail`. |
| Notifications | one file: `lib/checkin/meal-reaction-nudge.ts` (local, +2.5h), fired from `save-meal`. `notification-icon.png` missing. |
| Haptics | `expo-haptics` — **zero usages**. |
| Secure store | `expo-secure-store` — **zero usages**; the Supabase session sits in **AsyncStorage** (not secure). |
| Sharing / export | `expo-sharing` lazily in `report/pdf.ts`, `report-export.ts`, `account/export-data.ts`. |
| HealthKit | permissions declared in `app.json`; **no HealthKit code**; wearables via Thryve. |
| Speech / mic | `useWhisperMic`, `useSpeechRecognition`, `useVoiceDictation`, `useMealDictation` — chat + describe-a-meal. |

## 12-line summary
1. Root layout stacks Gesture→SafeArea→Query→StatusBar→WebMobileFrame→AuthGate→Slot+HelpLayer, holding on `useFonts` (DM Serif Display + DM Sans).
2. Gate order: profile-read splash → language → access window → onboarding (members target only) → consent → app; `pendingRoute` keeps email deep links across the sign-in remount.
3. Onboarding rule: `onboarding_completed_at` **and** all five energy inputs; read failures fail open; `resumeRoute()`.
4. Two onboarding flows: **`ob-*` (8 screens) LIVE mandatory**; **`q1-*` (6 screens) optional Day-1 assessment** of the 5-day program.
5. Tabs: Home/Trends/Food/Library/Profile (lucide `Home`, `TrendingUp`, `Salad`, `BookOpen`, `User`); `chat` hidden; **no center FAB**.
6. Floating 66px glass pill bar, mirrored by `FloatingNavBar` for the screens stack.
7. Deep-link scheme `functionalps`; no inbound deep-link handling beyond expo-router defaults.
8. Theme: light-only, forest/cream/gold/charcoal/stone tokens, locked macro + score + scale palettes, `radii {12,16,22,24,200}`, 7 spotlight walls (default Sage).
9. i18n EN/FR, English-string-as-key with generated + hand FR catalogs, overlays for copy modules; locale preference `auto|en|fr`, mirrored to `nb_patient_app_profiles.locale`.
10. Dark/parked: AI chat + `nutrition-ai` OFF; Habits (`plan*`) redirect; `your-resources` + `resource/[id]` PARKED; coverage nudge off.
11. 15 route files dead/legacy/dev-only with zero inbound references.
12. Native surface is narrower than the manifest: expo-camera/haptics/secure-store unused; sessions in AsyncStorage; photos via image-picker; notifications one local nudge; sharing for PDFs/export.
