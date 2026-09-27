# Local reminders (scheduled on the phone)

What the iPhone schedules by itself. The server pushes (practitioner message, report ready, care plan, meal needs input) are separate and not covered here.

- **Plan:** `FunctionAlps/Sources/Core/Notifications/NotificationPlanner.swift`
- **Scheduler:** `FunctionAlps/Sources/Core/Notifications/LocalNotifications.swift`
- **Engine:** `FunctionAlps/Sources/Services/NotificationService.swift`
- **Preferences:** `FunctionAlps/Sources/Models/NotificationPrefs.swift` (row `patient_notification_preferences`)
- **Strings:** `FunctionAlps/Sources/Resources/Localizable.xcstrings` (`notif.*`)

## How it works

- The phone plans **7 days ahead** and replaces the pending set each time it re-plans. Re-planning happens:
  - when Home loads,
  - when notification settings change.
- After a meal is logged, its follow-up reminder is added immediately.
- **A reminder is never scheduled for something already done today.** Check-ins done → no check-in reminder. Meal logged in the window → no meal reminder. Meal rated → no follow-up.
- **Quiet hours** are on by default (**22:00–07:30**). A reminder that would fire inside them moves to the end of the window (07:30).
- Every request id starts with `fa.`, so the app never touches notifications it didn't create.
- Foreground: the banner still shows.
- Sound: default.
- Grouped by `threadId` = the kind.

## The reminders

### 1. Morning check-in

| | |
|---|---|
| **Id** | `checkin.morning.<yyyy-mm-dd>` |
| **When** | Daily at the member's time (default **08:00**) |
| **Skipped if** | Morning check-in already done today |
| **Setting** | `morning_checkin_enabled` / `morning_checkin_time` (default on) |
| **Title (EN)** | Good morning ☀️ |
| **Body (EN)** | How did you sleep, and what does today need? Under a minute. |
| **Title (FR)** | Bonjour ☀️ |
| **Body (FR)** | Comment avez-vous dormi, et de quoi cette journée a-t-elle besoin ? Moins d'une minute. |
| **Tap opens** | `functionalps://checkin/morning` |
| **Buttons** | Check in now / Faire le bilan |
| **String keys** | `notif.morning.title`, `notif.morning.body` |

### 2. Evening check-in

| | |
|---|---|
| **Id** | `checkin.evening.<yyyy-mm-dd>` |
| **When** | Daily at the member's time (default **20:45**) |
| **Skipped if** | Evening check-in already done today |
| **Setting** | `daily_checkin_reminder_enabled` / `daily_checkin_time` (default on) |
| **Title (EN)** | Look back on your day 🌙 |
| **Body (EN)** | Energy, focus, mood and digestion — how did the day actually go? |
| **Title (FR)** | Revenez sur votre journée 🌙 |
| **Body (FR)** | Énergie, concentration, humeur et digestion — comment s'est passée la journée ? |
| **Tap opens** | `functionalps://checkin/evening` |
| **Buttons** | Check in now / Faire le bilan |
| **String keys** | `notif.evening.title`, `notif.evening.body` |

### 3. Lunch not logged

| | |
|---|---|
| **Id** | `meal.lunch.<yyyy-mm-dd>` |
| **When** | Daily at **13:30** (fixed) |
| **Skipped if** | A meal was logged today between 11:00 and 13:30 |
| **Setting** | `meal_reminders_enabled` (default on; shared with dinner) |
| **Title (EN)** | No lunch photo yet? |
| **Body (EN)** | A quick snap now keeps today's picture whole. |
| **Title (FR)** | Pas encore de photo du déjeuner ? |
| **Body (FR)** | Un cliché maintenant garde la journée complète. |
| **Tap opens** | `functionalps://food` |
| **Buttons** | Log it / Enregistrer |
| **String keys** | `notif.lunch.title`, `notif.lunch.body` |

### 4. Dinner not logged

| | |
|---|---|
| **Id** | `meal.dinner.<yyyy-mm-dd>` |
| **When** | Daily at **20:15** (fixed) |
| **Skipped if** | A meal was logged today between 17:30 and 20:15 |
| **Setting** | `meal_reminders_enabled` (default on; shared with lunch) |
| **Title (EN)** | Dinner not logged |
| **Body (EN)** | Photograph or describe it — 20 seconds. |
| **Title (FR)** | Dîner non enregistré |
| **Body (FR)** | Photographiez-le ou décrivez-le — 20 secondes. |
| **Tap opens** | `functionalps://food` |
| **Buttons** | Log it / Enregistrer |
| **String keys** | `notif.dinner.title`, `notif.dinner.body` |

### 5. How do you feel after that meal?

| | |
|---|---|
| **Id** | `meal.reaction.<mealId>` |
| **When** | **2.5 h after each meal** is logged (once per meal) |
| **Skipped if** | The meal already has a reaction (checked against the backend and ratings made on this phone) |
| **Setting** | `post_meal_followup_enabled` (default on) |
| **Title (EN)** | How do you feel after that meal? |
| **Body (EN)** | Energy, digestion, bloating — 10 seconds, and it teaches the pattern. |
| **Title (FR)** | Comment vous sentez-vous après ce repas ? |
| **Body (FR)** | Énergie, digestion, ballonnements — 10 secondes, et le schéma s'apprend. |
| **Tap opens** | `functionalps://meal/<mealId>?rate=1` |
| **Buttons** | Rate it / Évaluer · Felt fine / Ça allait |
| **String keys** | `notif.reaction.title`, `notif.reaction.body` |

"Felt fine" rates the meal without opening the app. It saves overall 7 and digestion 7 with zero symptoms. The code comment in `NotificationService.quickFine` says "8/10", which does not match what is saved.

### 6. Weekly summary

| | |
|---|---|
| **Id** | `weekly.<yyyy-mm-dd>` |
| **When** | **Sunday 18:00** (fixed) |
| **Skipped if** | — |
| **Setting** | `weekly_summary_enabled` (default on) |
| **Title (EN)** | Your week at a glance |
| **Body (EN)** | Seven days of meals, check-ins and nights — see what moved. |
| **Title (FR)** | Votre semaine en un coup d'œil |
| **Body (FR)** | Sept jours de repas, de bilans et de nuits — voyez ce qui a bougé. |
| **Tap opens** | `functionalps://trends` |
| **Buttons** | none |
| **String keys** | `notif.weekly.title`, `notif.weekly.body` |

### 7. Apple Health hasn't synced

| | |
|---|---|
| **Id** | `wearable.stale.<yyyy-mm-dd>` |
| **When** | **3 days after the last Apple Health sync** |
| **Skipped if** | Apple Health not connected |
| **Setting** | none (no toggle) |
| **Title (EN)** | Apple Health hasn't synced for 3 days |
| **Body (EN)** | Open FunctionAlps once so your nights and steps catch up. |
| **Title (FR)** | Apple Santé n'a pas synchronisé depuis 3 jours |
| **Body (FR)** | Ouvrez FunctionAlps une fois pour rattraper vos nuits et vos pas. |
| **Tap opens** | `functionalps://devices` |
| **Buttons** | none |
| **String keys** | `notif.stale.title`, `notif.stale.body` |

### Retired: midday check-in

Kind `checkin.midday`. It is never planned. The kind stays only so that re-planning clears midday reminders left pending by an older build. The `midday_checkin_*` columns stay because the web app shares the row.

## Summary

| # | Reminder | Time | Can the member turn it off? | Can the member change the time? |
|---|---|---|---|---|
| 1 | Morning check-in | 08:00 | Yes | Yes |
| 2 | Evening check-in | 20:45 | Yes | Yes |
| 3 | Lunch not logged | 13:30 | Yes (with dinner) | No |
| 4 | Dinner not logged | 20:15 | Yes (with lunch) | No |
| 5 | After-meal feeling | meal + 2.5 h | Yes | No |
| 6 | Weekly summary | Sun 18:00 | Yes | No |
| 7 | Apple Health stale | last sync + 3 days | No | No |

Quiet hours (default 22:00–07:30, adjustable) push any of these to the end of the window.

## Permission

The iOS prompt is asked once, at one of these moments:

- the first meal logged,
- the first check-in completed,
- the button in Settings → Notifications.

Nothing is scheduled until the member allows notifications.
