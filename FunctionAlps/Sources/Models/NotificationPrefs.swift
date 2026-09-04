import Foundation

/// `patient_notification_preferences` as the phone reads and writes it (one row per member; the web app
/// shares the evening check-in columns). Times are the member's wall clock, `HH:mm`.
struct NotificationPrefs: Sendable, Equatable {
    var morningEnabled = true
    var morningTime = "08:00"
    var middayEnabled = true
    var middayTime = "14:30"
    var eveningEnabled = true          // daily_checkin_reminder_enabled
    var eveningTime = "19:00"          // daily_checkin_time
    var mealRemindersEnabled = true
    var postMealFollowupEnabled = true
    var weeklySummaryEnabled = true
    var messagesEnabled = true
    var reportsEnabled = true
    var carePlanEnabled = true
    var quietHoursEnabled = true
    var quietStart = "22:00"
    var quietEnd = "07:30"
    var pushEnabled = true
    var timezone = TimeZone.current.identifier

    static let `default` = NotificationPrefs()

    /// `HH:mm` → (hour, minute); junk → nil.
    static func parse(_ hhmm: String) -> (hour: Int, minute: Int)? {
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// `'HH:MM:SS'` or `'HH:MM'` from PostgREST → `HH:mm`.
    static func hhmm(_ raw: String?, fallback: String) -> String {
        guard let raw, let p = parse(String(raw.prefix(5))) else { return fallback }
        return String(format: "%02d:%02d", p.hour, p.minute)
    }
}

/// The PostgREST row (snake_case via the decoder / encoder strategies).
struct NotificationPrefsRow: Codable, Sendable {
    var patientId: String?
    var morningCheckinEnabled: Bool?
    var morningCheckinTime: String?
    var middayCheckinEnabled: Bool?
    var middayCheckinTime: String?
    var dailyCheckinReminderEnabled: Bool?
    var dailyCheckinTime: String?
    var mealRemindersEnabled: Bool?
    var postMealFollowupEnabled: Bool?
    var weeklySummaryEnabled: Bool?
    var messagesEnabled: Bool?
    var reportsEnabled: Bool?
    var carePlanEnabled: Bool?
    var quietHoursEnabled: Bool?
    var quietHoursStart: String?
    var quietHoursEnd: String?
    var pushEnabled: Bool?
    var timezone: String?
    var apnsToken: String?
    var apnsEnvironment: String?
    var apnsTokenUpdatedAt: String?
    var devicePlatform: String?
    var appVersion: String?

    static let columns = "patient_id,morning_checkin_enabled,morning_checkin_time,midday_checkin_enabled,midday_checkin_time,daily_checkin_reminder_enabled,daily_checkin_time,meal_reminders_enabled,post_meal_followup_enabled,weekly_summary_enabled,messages_enabled,reports_enabled,care_plan_enabled,quiet_hours_enabled,quiet_hours_start,quiet_hours_end,push_enabled,timezone"

    var prefs: NotificationPrefs {
        var p = NotificationPrefs()
        p.morningEnabled = morningCheckinEnabled ?? p.morningEnabled
        p.morningTime = NotificationPrefs.hhmm(morningCheckinTime, fallback: p.morningTime)
        p.middayEnabled = middayCheckinEnabled ?? p.middayEnabled
        p.middayTime = NotificationPrefs.hhmm(middayCheckinTime, fallback: p.middayTime)
        p.eveningEnabled = dailyCheckinReminderEnabled ?? p.eveningEnabled
        p.eveningTime = NotificationPrefs.hhmm(dailyCheckinTime, fallback: p.eveningTime)
        p.mealRemindersEnabled = mealRemindersEnabled ?? p.mealRemindersEnabled
        p.postMealFollowupEnabled = postMealFollowupEnabled ?? p.postMealFollowupEnabled
        p.weeklySummaryEnabled = weeklySummaryEnabled ?? p.weeklySummaryEnabled
        p.messagesEnabled = messagesEnabled ?? p.messagesEnabled
        p.reportsEnabled = reportsEnabled ?? p.reportsEnabled
        p.carePlanEnabled = carePlanEnabled ?? p.carePlanEnabled
        p.quietHoursEnabled = quietHoursEnabled ?? p.quietHoursEnabled
        p.quietStart = NotificationPrefs.hhmm(quietHoursStart, fallback: p.quietStart)
        p.quietEnd = NotificationPrefs.hhmm(quietHoursEnd, fallback: p.quietEnd)
        p.pushEnabled = pushEnabled ?? p.pushEnabled
        p.timezone = timezone ?? p.timezone
        return p
    }

    /// The full write for an upsert on `patient_id`.
    static func write(_ p: NotificationPrefs, patientId: String) -> NotificationPrefsRow {
        NotificationPrefsRow(
            patientId: patientId,
            morningCheckinEnabled: p.morningEnabled, morningCheckinTime: p.morningTime + ":00",
            middayCheckinEnabled: p.middayEnabled, middayCheckinTime: p.middayTime + ":00",
            dailyCheckinReminderEnabled: p.eveningEnabled, dailyCheckinTime: p.eveningTime + ":00",
            mealRemindersEnabled: p.mealRemindersEnabled, postMealFollowupEnabled: p.postMealFollowupEnabled,
            weeklySummaryEnabled: p.weeklySummaryEnabled, messagesEnabled: p.messagesEnabled, reportsEnabled: p.reportsEnabled, carePlanEnabled: p.carePlanEnabled,
            quietHoursEnabled: p.quietHoursEnabled, quietHoursStart: p.quietStart + ":00", quietHoursEnd: p.quietEnd + ":00",
            pushEnabled: p.pushEnabled, timezone: p.timezone
        )
    }
}

/// `apns_token` + device facts, written on every launch that has a token.
struct PushTokenWrite: Encodable, Sendable {
    let patientId: String
    let apnsToken: String
    let apnsEnvironment: String
    /// ISO 8601 (`ISO8601.string`).
    let apnsTokenUpdatedAt: String
    let devicePlatform: String
    let appVersion: String
    let timezone: String
}
