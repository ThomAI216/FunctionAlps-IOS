# Wearable data catalogue — what each source gives, what we store, where it could show

Researched 2026-11-06 from the vendors' official API documentation (Oura OpenAPI 1.43, WHOOP OpenAPI, Polar v4 Swagger,
Withings openapi.yaml, Suunto APIZone, Garmin's public programme pages + OAuth2 PKCE PDF, Apple HealthKit docs, Dexcom
v3 docs, Ultrahuman developer docs), compared line by line with `supabase/functions/_shared/wearables/*.ts` and the
iOS HealthKit reader. Where a fact is not from an official page it says so. This is the spec the app (iOS), the
members' dashboard (MEMBERS) and the practitioner dashboard (CLINICAL) build from; update it when an adapter changes.

Catalogue ids are `wearable_data_types` (see `core.ts` `T`). "Stored" = written to `wearable_daily` / `wearable_epoch`
today; "raw" = kept only inside the vendor payload / `details`.

---

## 1. Where each source stands (2026-11-06)

| Source | Status on CM OS | Connect works? | Live members | Fixed today |
|---|---|---|---|---|
| Apple Health (relay, on the phone) | always on | yes | 4 phones | — |
| Withings | available | **yes** — proven (oauth → webhooks → nightly pulls) | 1 (scale only) | — (fix list §5) |
| Oura | available | **was broken** (scope `spo2Daily` is not an Oura scope) | 0 | scope, User-Agent, PKCE, 403 handling, distance, deleted sleeps |
| Polar | available | **was broken** (identity call to a non-existent `/v4/data/profile`; scope `ppi:read` undocumented) | 0 | connect + whole data path rebuilt from the official Swagger |
| WHOOP | available | probably (one webhook signature mismatch on 2026-09-14 is unexplained) | 0 | — (fix list §5) |
| Garmin | planned | adapter rebuilt 2026-11-06, waits for keys + spec PDFs (Starter tier = push only, no history) | 0 | — |
| Suunto | planned | adapter has three data bugs (§5); access is free after a company application, ≤ 2 weeks review | 0 | — |
| Google / Fitbit | planned | not pursued (paid restricted-scope security review). Fitbit data reaches us through Apple Health instead (§2.9) | — | — |
| Strava | removed | its API Policy forbids storing / sharing its data | — | — |
| Ultrahuman | not built | partner API incl. `cgm_data` on request — application email drafted | — | — |
| CGM (Dexcom, Libre) | not built | Dexcom G7 reaches Apple Health (3 h delay); Libre only via Ultrahuman M1 or LibreView — Abbott email drafted | — | — |

**The fixes for Oura and Polar reach members only when the branch is merged to `main`** (that deploys the edge
functions). Until then a member who taps Connect on Oura or Polar gets "The connection didn't complete".

---

## 2. Per source — available, stored, gap

### 2.1 Apple Health (the iPhone relay)
- **Read today (15 types + sleep + workouts):** steps, walking/running distance, active and basal energy, exercise
  minutes, flights, resting HR, HR, HRV (SDNN), respiratory rate, SpO₂, VO₂max, weight, body-fat %, body temperature,
  sleep stages, workouts (energy + walking/running distance only).
- **Worth adding (official HealthKit types):** `bloodGlucose` (Dexcom G7 with 3 h delay, Ultrahuman M1, Google Health
  app; parked today — needs a Privacy Notice update first) · `appleSleepingWristTemperature` (Apple Watch S8+, nightly) ·
  `timeInDaylight` · `leanBodyMass`, `waistCircumference` · `dietaryWater`, `dietaryCaffeine` (planned consumption
  tracking) · `menstrualFlow` and the cycle types · `bloodPressureSystolic/Diastolic` · `heartRateVariabilityRMSSD`
  (new in iOS 27; Apple does not say yet whether the Watch writes it) · `HKUserAnnotatedMedication` + dose events
  (supplement adherence, iOS 26) · `HKStateOfMind`, `mindfulSession`.
- **Not exposed to apps:** Apple's Sleep Score and the watchOS 27 readiness score.
- **Housekeeping:** the permission text in `project.yml` does not mention every type read today; workouts lose cycling
  and swimming distance; the unused `standHours` slot.

### 2.2 Withings (live)
- **Stored:** weight and body composition (fat-free, fat, fat %, muscle, bone, water), height, BP, SpO₂, temperatures,
  PWV, VO₂max, AFib result; sleep summary (durations, efficiency, score, HR, RR, snoring, breathing disturbances,
  start/end); daily activity (steps, distance, floors, active/total kcal, HR zones); workouts.
- **Gaps with value:** U-Scan urine (pH, specific gravity, ketones, vitamin C, calcium/creatinine — free plan, notify
  `appli=63`, needs new ids) · glucose (code 119 → 1000107) · visceral fat, BMR, metabolic age, extra/intracellular
  water (Advanced Biomarkers plan) · sleep timing (`night_events`, wake-up latency, out-of-bed count, the hypnogram) ·
  soft/moderate/intense minutes · device model ("Withings Body+").
- **HRV:** not in the sleep summary under the names we ask for (`sdnn_1`, `rmssd` are high-frequency fields; the summary
  has `rmssd_start_avg` / `rmssd_end_avg`). Many sleep metrics are Advanced-Biomarkers-only on a free-plan app.
- **Plan limits:** free plan = 10 active users until Withings reviews the app; **from 2026-10-12 newly created Withings
  accounts need Withings+ to share with a free-plan app** (also through Apple Health).

### 2.3 Oura (available)
- **Stored:** main sleep (durations, efficiency, latency, restless periods, sleep HR, lowest HR, breathing, start/end,
  5-min phases, HR series), sleep score, readiness score, temperature deviation, steps, kcal, activity minutes, MET,
  SpO₂ + breathing-disturbance index, VO₂max, daytime stress/recovery minutes, workouts, daytime HR.
- **Gaps:** overnight HRV (`average_hrv`, ms, mean of 5-min samples — kept raw by decision D4) · temperature *trend*
  deviation · readiness contributors (sleep regularity, HRV balance…) · resilience level · cardiovascular age + PWV ·
  lifestyle tags (`enhanced_tag`, needs the `tag` scope) · optimal bedtime window · non-wear time · sessions
  (breathing / meditation HR + HRV) · rest mode periods.
- **Note:** Oura counts the activity day from 4 a.m.; its "lowest HR" is computed differently from the Oura app.

### 2.4 WHOOP (available)
- **Stored:** recovery %, resting HR, HRV (RMSSD, ms, per sleep), SpO₂, skin temperature, sleep stages + performance,
  respiratory rate, day strain + kcal, workouts with HR zones.
- **Gaps:** daily steps (`cycle.step_count`, added 2026-09-23) · sleep need / sleep debt · sleep consistency ·
  disturbance and cycle counts · naps (dropped today) · weight/height history.
- **Not in the API at all:** continuous HR, HRV series, VO₂max, stress monitor, cycle, BP, journal.

### 2.5 Polar (available; data path rebuilt today)
- **Stored from today's rebuild:** overnight HRV (RMSSD, ms, 0.5–4.5 h after sleep start → 3106), Nightly Recharge code
  1–6, ANS status, sleep (asleep, span, REM/deep/light/wake, efficiency, interruptions, score, Sleep Charge 1–5,
  start/end).
- **Gaps with value:** **fuel use per training session (carbohydrate / fat / protein %)** — unique to Polar and relevant
  to a nutrition practice · session kcal, recovery time, cardio load · continuous HR · daily steps · weight (calendar) ·
  orthostatic / fitness / SpO₂ tests · skin temperature.

### 2.6 Garmin (planned; adapter rebuilt, field names VERIFY until the spec PDFs)
- **Mapped:** daily steps / distance / floors / kcal / intensity minutes / resting + average HR / stress; sleep with
  stages and score; Body Battery (day high/low); body composition; skin temperature deviation; BP; VO₂max; workouts;
  menstrual cycle day. HRV mapped but held until the spec confirms RMSSD.
- **Gaps:** BMR, 15-min epochs (MET/intensity), all-day stress and Body Battery series, Pulse Ox and respiration series,
  cycle phase/length, body water %.
- **Starter tier:** push only and **no history** — data starts the day a member connects; a missed push is lost.

### 2.7 Suunto (planned)
- **API offers:** workouts (incl. R-R intervals), 24/7 activity (HR, steps, energy, SpO₂, HRV ~10 min), daily step and
  energy totals, sleep (stages, latency, WASO, HR, HRV, quality score, SpO₂), recovery balance and stress state — all
  with webhooks.
- **Access:** free; company application through Suunto's partner form, reviewed weekly ("maximum two week waiting
  period"); development keys first (low limits), production after a content form.

### 2.8 Ultrahuman (not built)
- **Partner API:** sleep (stages, score, efficiency, HR, HRV, hypnogram), recovery, temperature + deviation, steps,
  VO₂max, movement; **CGM (M1): glucose series (mg/dL), metabolic score, variability, average glucose, time in target**
  — `cgm_data` scope "granted on request". Daily pull (no webhooks). M1 is sold in Switzerland (CHF 249 / 4 weeks).

### 2.9 Google Health (Fitbit) — through Apple Health
The Google Health app (renamed from Fitbit, 2026-05-07) writes to Apple Health: steps, VO₂max, floors, active kcal,
distance, exercise, body temperature, sleep sessions **with stages**, HR, resting HR, SpO₂, respiratory rate, blood
glucose, weight, body-fat %, nutrition and water, mindfulness, cycle data. **Not HRV, not skin temperature.** So a
Fitbit member is mostly covered by the relay today.

### 2.10 CGM
- **Dexcom G7** (sold in CH): its app writes to Apple Health with a 3 h delay → reading `bloodGlucose` is enough; the
  Dexcom API has the same 3 h delay outside the US. Dexcom is not being pursued (owner, 2026-11-06).
- **FreeStyle Libre** (most common in CH): no Apple Health write, no public API. Routes: Ultrahuman M1 (Libre sensors),
  a LibreView professional account (manual viewing), or an Abbott-licensed partner. Abbott CH email drafted.

---

## 3. By data family — who supplies it, and where it could show

| Family | Sources | Member app (iOS) | Members' web dashboard | Practitioner dashboard |
|---|---|---|---|---|
| Sleep (duration, stages, timing, score) | Apple Health, Withings, Oura, WHOOP, Polar, Garmin, Suunto, Ultrahuman | Home: last night + 14-day trend (exists, Apple-based) | Sleep card | Sleep lane (exists) + bedtime regularity |
| Overnight HRV / recovery | WHOOP (stored), Polar (stored now), Oura / Withings / Garmin (raw until D4), Apple Watch SDNN | Readiness on Home (uses own baseline) | Recovery trend | HRV lane — never mix SDNN with RMSSD |
| Resting / sleeping HR | all | trend | trend | lane |
| Activity & energy (steps, kcal, intensity) | all; Polar/WHOOP steps are gaps | Home card | Activity card | lane + weekly load |
| Workouts & fuel use | all; **Polar carbs/fat/protein %** | workout list | — | session list with fuel split |
| Body composition | Withings (live), Garmin, Apple Health | weigh-in trend | body card | composition lane |
| Temperature (deviation) | Oura, WHOOP, Garmin, Apple Watch wrist temp | — | cycle / illness context | lane, shown neutrally |
| Stress / resilience | Oura, Garmin, Suunto | — | — | context lane |
| Blood pressure | Withings, Garmin, Apple Health | — | — | readings list |
| Glucose (CGM) | Apple Health (Dexcom, Ultrahuman, Google Health), Ultrahuman API, Withings code 119 | meal-response view (after the notice update) | glucose card | daily mean, variability, time in range (ids 1000114–1000117 reserved) |
| Cycle | Garmin, Apple Health, Google Health relay | — | — | phase context for nutrition |
| Urine biomarkers | Withings U-Scan | — | — | new lane |

Every display of vendor data needs that vendor's attribution where its terms ask (Garmin: "Garmin [device model]" beside
the title, also on derived scores; WHOOP: "Data by WHOOP", its recovery colours, no renamed metrics; Polar: credit "Polar
Ecosystem"; Dexcom: "Dexcom Data", units + timestamp, never "blood glucose").

---

## 4. Terms that constrain storage and practitioner viewing — for a legal read before members

- **Oura** (API Agreement, 2026-06-08): §4(a)(xx) lists "aggregating, caching, or storing … User Data" as prohibited
  without Oura's written consent; §3(m) "not stored or retained beyond the duration strictly necessary"; delete within
  72 h on request and when the member stops being a client; practitioner viewing only with the member's prior express
  consent; no AI use at all.
- **WHOOP** (API Terms, 2026-10-06): no "permanent copies"; **no use of the APIs "to offer … any medical, legal, or other
  professional advice"**; no AI; opt-in consent before anyone else sees the data.
- **Withings** (Developer Software Agreement): no queries "not in response to end user actions" (our nightly reconcile?);
  §7(vi) on identifying data "brought to the attention of a health care professional" is ambiguous.
- **Garmin**: the API Brand Guidelines (official, v6.30.2025) require attribution on every display and on derived
  scores. The licence itself (Rev. B, 2026) is behind the portal login; a third-party summary says deriving income needs
  Garmin's written permission (a paid membership built on Garmin data?) and AI needs a transparency statement +
  withdrawable consent — read the version you accepted.
- **Polar** (API Licence): storage allowed if disclosed; credit Polar; revoke and delete on the member's request.
- **Strava**: excluded (storage, sharing, AI all forbidden).

Our storage model (`wearable_daily` / `wearable_epoch`, shown to the member's practitioner, used by the scoring engine)
needs to be checked against Oura's and WHOOP's clauses in particular.

---

## 5. Fix list (found 2026-11-06; Oura and Polar already fixed on the branch)

1. **WHOOP** — vendor deletions (`sleep.deleted`, `workout.deleted`, `recovery.deleted`) are never applied; HR-zone
   buckets are shifted one zone against WHOOP's own labels; `cycle.step_count` not stored; naps dropped.
2. **Withings** — no pagination (`more` / `offset`) on getmeas / getactivity / getworkouts; a 31-day backfill exceeds the
   7-day sleep limit; attrib 5 and 8 measures dropped; AFib code 0–13 written to a BOOLEAN id; snoring seconds written to
   a BOOLEAN id; error 601 not treated as a rate limit; the HRV fields asked of the summary are the wrong ones.
3. **Suunto** — daily statistics call uses the wrong parameters and shape (no daily steps ever); workout HR read from the
   wrong field (`hrdata.workoutAvgHR`); sleep `Duration` is time in bed (→ 2301), asleep = deep + light + REM; 31-day
   backfill exceeds the 28-day limit.
4. **Platform** — vendor deletion events are not applied anywhere (`WebhookEvent.deleted` is never acted on).
5. **Oura** — delete events not subscribed; overnight HR written twice (sleep series and `/heartrate`).

---

## 6. Decisions for Thomas

1. Merge the branch to `main` (deploys the Oura and Polar fixes, the Garmin adapter and the readiness probe).
2. Legal read of §4 before practitioner-facing displays of Oura / WHOOP data.
3. D4: write overnight HRV for Oura and Garmin once their definitions are accepted (Polar and WHOOP are official RMSSD).
4. Glucose: approve a Privacy Notice update so the app can read `bloodGlucose` from Apple Health.
5. Which gaps to build first (suggestion: Polar fuel use, WHOOP steps, Withings urine + glucose, Apple Health
   wrist temperature + daylight + water/caffeine).
6. Withings: the 10-user free-plan cap and Withings+ for new accounts.
