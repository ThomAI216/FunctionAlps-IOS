# API_MAP — the backend surface the patient app uses, and the smallest boundary for iOS (Task 2)

## 1. What exists (no invention)
There is no Next.js API for the patient app. The FunctionAlps "API" the app talks to today is **CM OS itself**:

| Kind | Endpoint pattern | Used for | Auth |
|---|---|---|---|
| Auth | `POST {SUPABASE_URL}/auth/v1/token?grant_type=password\|refresh_token`, `POST /auth/v1/logout`, `GET /auth/v1/user`, `POST /auth/v1/signup`, `POST /auth/v1/recover`, OAuth `/auth/v1/authorize?provider=google` | sign in/up/out, refresh, reset | `apikey` (publishable) + bearer |
| Data | `GET/POST/PATCH/DELETE {SUPABASE_URL}/rest/v1/{table}?{filters}` (PostgREST) | 41 tables, own rows under RLS | `apikey` + member bearer |
| Functions | `POST {SUPABASE_URL}/rest/v1/rpc/{name}` | 12 client RPCs (identity, consent, library, messages) | same |
| Server logic | `POST {SUPABASE_URL}/functions/v1/{name}` | 17 edge functions (meal analysis, transcription, registration, Q1, feedback, gates, deletion, score tips, reports, Thryve) | `apikey` + member bearer (functions verify the JWT themselves) |
| Files | `{SUPABASE_URL}/storage/v1/object/meal-images/…` (+ signed URLs) | meal photos | bearer |
| Realtime | `wss://{SUPABASE_URL}/realtime/v1` | habits + meal-analysis updates | bearer |

Which flows use Server Actions: **none** (Expo app; MEMBERS/CLINICAL use server actions but are out of scope). Which components call Supabase directly: essentially all data hooks/stores (`lib/**`) plus a few screens (`chat.tsx`, `weekly-theme.tsx`, `log-supplements.tsx`, `profile-wearables.tsx`). Business logic split: see DATA_MODEL §"Server-side vs client-side truth".

## 2. Smallest API boundary for native iOS (recommendation)
Do **not** build `api.functionalps.ch` before Milestone 1 (PRD §7 says "determine after auditing"; §38 says no automation before the manual path works). The audited backend already exposes everything M1 needs with zero server change, and RLS is the authorization. So:

1. **M1 (now):** iOS talks to CM OS REST directly, but only through `Core/API` (`SupabaseAuthClient`, `PostgRESTClient`, `EdgeFunctionClient`) behind the `FunctionAlpsBackend` protocol. Features see domain operations only. This is the "SEPARATE" step of PRD §63 done in the client.
2. **Phase A–D:** keep using existing edge functions and RPCs; for **writes** with fragile schema rules (`nb_patient_app_profiles` UPDATE-then-INSERT, `nb_meal_logs` pending-row shape, check-in upserts) prefer adding **RPCs or edge functions** on CM OS (`member_save_profile`, `member_log_meal`, `member_submit_checkin`) so the rule lives once, server-side, shared with the Expo app during the transition. These are the first real `/v1` operations.
3. **Later:** `api.functionalps.ch` fronts the same operations (a thin gateway or self-hosted Supabase in Switzerland). Swift swaps `SupabaseBackend` for `GatewayBackend`; `openapi.yaml` is the contract both must honour.

## 3. The v1 contract (`openapi.yaml`)
Written as the **domain** contract the Swift client codes against. Each operation documents its current CM OS implementation. Operations in M1: `auth.login`, `auth.refresh`, `auth.logout`, `me` (identity + profile), `me/today` (meals, check-in, unread count). Planned operations are listed with `x-status: planned` so the spec stays honest.

## 4. Error contract
HTTP status → `AppError` (`Core/Errors/AppError.swift`): 400/409/422 validation (PostgREST/GoTrue message extracted), 401 unauthorized (refresh + retry once), 403 forbidden, 404 notFound, 5xx server, transport → offline/network. Bodies from GoTrue (`{error_code,msg}` / `{error,error_description}`) and PostgREST (`{code,message,details,hint}`) are both parsed.
