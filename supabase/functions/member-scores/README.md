# Edge functions owned by the iOS app

`member-scores` computes the Functional Score, the three pillars, Gut Intelligence and their
14-day series **on the server**, under the caller's JWT. `engine/` is a verbatim copy of the
Expo app's pure scoring modules (`lib/health/*`, `lib/nutrition/{snapshot,macros-view}`,
`lib/data/{nutrients,health-details}`, `lib/checkin/{marker-trends,score-bands,load-today}`,
`lib/utils/tdee`, `lib/dates/local-day`) with imports rewritten and the React/i18n tails removed.

Re-copy after any change to those modules in `FunctionAlps-APP` (the script lives in the session
handoff `.context/agents/2026-09-03_ios-testflight-auth-food.md` in STUDIO); deploy with the
Supabase MCP `deploy_edge_function` (verify_jwt = true).

Request: `POST /functions/v1/member-scores` `{ "tzOffsetMinutes": 120 }` (minutes east of UTC).
Response: `{ day, composite, vitality, metabolic, nutrition, gut, compositeSeries14d, inputs }`.
