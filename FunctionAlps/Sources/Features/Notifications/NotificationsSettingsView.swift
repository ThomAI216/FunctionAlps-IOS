import SwiftUI
import UserNotifications

/// Settings → Notifications. The member owns every reminder: which, when, and the quiet window.
/// Changes save to `patient_notification_preferences` and re-plan the phone's pending set at once.
struct NotificationsSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var prefs: NotificationPrefs = .default
    @State private var loaded = false
    @State private var saveError: String?

    private var service: NotificationService { dependencies.notifications }

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "notif.settings.title", defaultValue: "Notifications"))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    permissionCard

                    SettingsSectionLabel(title: String(localized: "notif.section.checkins", defaultValue: "Check-ins"))
                    FACard {
                        VStack(spacing: 12) {
                            timedRow(String(localized: "notif.row.morning", defaultValue: "Morning check-in"), on: $prefs.morningEnabled, time: $prefs.morningTime)
                            timedRow(String(localized: "notif.row.midday", defaultValue: "Midday check-in"), on: $prefs.middayEnabled, time: $prefs.middayTime)
                            timedRow(String(localized: "notif.row.evening", defaultValue: "Evening check-in"), on: $prefs.eveningEnabled, time: $prefs.eveningTime)
                        }
                    }

                    SettingsSectionLabel(title: String(localized: "notif.section.meals", defaultValue: "Meals"))
                    FACard {
                        VStack(spacing: 12) {
                            toggleRow(String(localized: "notif.row.mealReminders", defaultValue: "Meal not logged"), sub: String(localized: "notif.row.mealReminders.sub", defaultValue: "Lunch at 13:30 and dinner at 20:15 — only when nothing was logged"), on: $prefs.mealRemindersEnabled)
                            toggleRow(String(localized: "notif.row.followup", defaultValue: "How do you feel?"), sub: String(localized: "notif.row.followup.sub", defaultValue: "2½ hours after each meal, once"), on: $prefs.postMealFollowupEnabled)
                        }
                    }

                    SettingsSectionLabel(title: String(localized: "notif.section.practitioner", defaultValue: "From your practitioner"))
                    FACard {
                        VStack(spacing: 12) {
                            toggleRow(String(localized: "notif.row.messages", defaultValue: "New message"), sub: nil, on: $prefs.messagesEnabled)
                            toggleRow(String(localized: "notif.row.reports", defaultValue: "Report ready"), sub: String(localized: "notif.row.reports.sub", defaultValue: "When your practitioner approves a report for you"), on: $prefs.reportsEnabled)
                            toggleRow(String(localized: "notif.row.careplan", defaultValue: "Care plan updated"), sub: nil, on: $prefs.carePlanEnabled)
                        }
                    }

                    SettingsSectionLabel(title: String(localized: "notif.section.rhythm", defaultValue: "Rhythm"))
                    FACard {
                        VStack(spacing: 12) {
                            toggleRow(String(localized: "notif.row.weekly", defaultValue: "Weekly summary"), sub: String(localized: "notif.row.weekly.sub", defaultValue: "Sunday, 18:00"), on: $prefs.weeklySummaryEnabled)
                            Divider().overlay(ProfilePalette.hairline)
                            toggleRow(String(localized: "notif.row.quiet", defaultValue: "Quiet hours"), sub: String(localized: "notif.row.quiet.sub", defaultValue: "Reminders wait until the window ends"), on: $prefs.quietHoursEnabled)
                            if prefs.quietHoursEnabled {
                                HStack(spacing: 12) {
                                    timeField(String(localized: "notif.quiet.from", defaultValue: "From"), $prefs.quietStart)
                                    timeField(String(localized: "notif.quiet.until", defaultValue: "Until"), $prefs.quietEnd)
                                }
                            }
                        }
                    }

                    if let saveError {
                        Text(saveError).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4).padding(.top, 10)
                    }

                    Text(String(localized: "notif.footer", defaultValue: "Notifications never carry health details — just a nudge and a link. Everything stays in the app."))
                        .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 18)
                }
                .padding(.horizontal, FASpacing.md)
                .padding(.bottom, FASpacing.navBarClearance)
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await service.refreshAuthorization()
            if let member = try? await dependencies.members.currentMember() { await service.loadPrefs(patientId: member.patientId, force: true) }
            prefs = service.prefs
            loaded = true
        }
        .onChange(of: prefs) { _, new in
            guard loaded else { return }
            Task {
                do {
                    try await service.save(new)
                    saveError = nil
                    await service.replan(snapshot: nil, wearables: dependencies.wearables)
                } catch let e as AppError { saveError = e.userMessage } catch { saveError = String(describing: error) }
            }
        }
    }

    // MARK: Permission

    @ViewBuilder
    private var permissionCard: some View {
        switch service.authorization {
        case .denied:
            FACard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.slash").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.red)
                        Text(String(localized: "notif.denied.title", defaultValue: "Notifications are off for FunctionAlps")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                    }
                    Text(String(localized: "notif.denied.body", defaultValue: "Turn them on in iOS Settings to receive your reminders and your practitioner's messages."))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                    FAButton(title: String(localized: "notif.denied.open", defaultValue: "Open iOS Settings"), style: .secondary) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            .padding(.bottom, 4)
        case .notDetermined:
            FACard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.brand)
                        Text(String(localized: "notif.ask.title", defaultValue: "Allow reminders")).font(FATypography.headline).foregroundStyle(FAColor.ink)
                    }
                    Text(String(localized: "notif.ask.body", defaultValue: "Your check-ins, meals not logged, how a meal felt, and news from your practitioner."))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                    FAButton(title: String(localized: "notif.ask.cta", defaultValue: "Turn on notifications")) {
                        Task { await service.askIfNeeded(); await service.replan(snapshot: nil, wearables: dependencies.wearables) }
                    }
                }
            }
            .padding(.bottom, 4)
        default:
            EmptyView()
        }
    }

    // MARK: Rows

    private func toggleRow(_ label: String, sub: String?, on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                if let sub { Text(sub).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(3) }
            }
        }
        .tint(FAColor.brand)
    }

    private func timedRow(_ label: String, on: Binding<Bool>, time: Binding<String>) -> some View {
        VStack(spacing: 8) {
            toggleRow(label, sub: nil, on: on)
            if on.wrappedValue {
                HStack {
                    Text(String(localized: "notif.at", defaultValue: "At")).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                    Spacer()
                    DatePicker("", selection: timeBinding(time), displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.compact).tint(FAColor.brand)
                }
            }
        }
    }

    private func timeField(_ label: String, _ time: Binding<String>) -> some View {
        HStack {
            Text(label).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
            Spacer()
            DatePicker("", selection: timeBinding(time), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.compact).tint(FAColor.brand)
        }
        .frame(maxWidth: .infinity)
    }

    /// `HH:mm` ⇄ a Date on today's calendar (only the clock part matters).
    private func timeBinding(_ text: Binding<String>) -> Binding<Date> {
        Binding<Date>(
            get: {
                let p = NotificationPrefs.parse(text.wrappedValue) ?? (hour: 8, minute: 0)
                return Calendar.current.date(bySettingHour: p.hour, minute: p.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                text.wrappedValue = String(format: "%02d:%02d", c.hour ?? 8, c.minute ?? 0)
            }
        )
    }
}
