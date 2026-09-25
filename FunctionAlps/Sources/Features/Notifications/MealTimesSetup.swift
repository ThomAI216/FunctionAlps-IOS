import SwiftUI

/// Home's one-time invitation (spec §5.2): shown to a member who allowed reminders but has not chosen a
/// single meal time yet. "Not now" retires it on this phone; Settings → Notifications → Meal times stays.
struct MealTimesSetupCard: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var showing = false

    var body: some View {
        let service = dependencies.notifications
        // Stays mounted while its sheet is open: saving ends the offer, and the sheet must close itself.
        if service.shouldOfferMealSetup || showing, let schedule = service.mealSchedule {
            FACard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.brand).accessibilityHidden(true)
                        Text(String(localized: "mealtimes.card.title", defaultValue: "When do you usually eat?"))
                            .font(FATypography.headline).foregroundStyle(FAColor.ink)
                    }
                    Text(String(localized: "mealtimes.card.body", defaultValue: "Set your meal times, and reminders come when you actually eat — never for a meal you skip."))
                        .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                    HStack(spacing: 10) {
                        FAButton(title: String(localized: "mealtimes.card.cta", defaultValue: "Set my times")) { showing = true }
                        FAButton(title: String(localized: "mealtimes.card.later", defaultValue: "Not now"), style: .tertiary) { service.markMealSetupOffered() }
                    }
                }
            }
            .sheet(isPresented: $showing) { MealTimesSetupSheet(schedule: schedule) }
        }
    }
}

/// "When do you usually eat?" — twenty seconds, prefilled (spec §5.2). Weekdays and the weekend, with Sunday
/// on its own when the member says it runs differently. Save makes every row theirs (`source = setup`).
struct MealTimesSetupSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MealSchedule
    @State private var sundayDifferent: Bool
    @State private var saving = false
    @State private var saveError: String?

    init(schedule: MealSchedule) {
        _draft = State(initialValue: schedule)
        _sundayDifferent = State(initialValue: !MealSlot.allCases.allSatisfy { schedule.isUniform($0, weekdays: [6, 7]) })
    }

    private struct DayGroup: Identifiable {
        let title: String
        let weekdays: [Int]
        var id: [Int] { weekdays }
    }

    private var groups: [DayGroup] {
        let weekdays = DayGroup(title: String(localized: "mealtimes.group.weekdays", defaultValue: "Weekdays"), weekdays: [1, 2, 3, 4, 5])
        if sundayDifferent {
            return [weekdays, DayGroup(title: MealScheduleView.dayName(6), weekdays: [6]), DayGroup(title: MealScheduleView.dayName(7), weekdays: [7])]
        }
        return [weekdays, DayGroup(title: String(localized: "mealtimes.group.weekend", defaultValue: "Weekend"), weekdays: [6, 7])]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "mealtimes.card.title", defaultValue: "When do you usually eat?"))
                        .font(FATypography.sans(22, .semibold, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                        .padding(.top, 28)
                    Text(String(localized: "mealtimes.setup.body", defaultValue: "Your reminders come at these times — only while that meal isn't logged yet. Switch off anything you don't usually have."))
                        .font(FATypography.sans(13, relativeTo: .callout)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                        .padding(.top, 6).padding(.bottom, 8)

                    ForEach(groups) { group in
                        SettingsSectionLabel(title: group.title)
                        FACard {
                            VStack(spacing: 12) {
                                ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { index, slot in
                                    if index > 0 { Divider().overlay(ProfilePalette.hairline) }
                                    MealSlotRow(
                                        slot: slot,
                                        enabled: Binding(get: { draft.entry(slot, weekday: group.weekdays[0]).enabled },
                                                         set: { draft.set(slot, weekdays: group.weekdays, enabled: $0, source: .setup) }),
                                        time: Binding(get: { draft.entry(slot, weekday: group.weekdays[0]).remindAt },
                                                      set: { draft.set(slot, weekdays: group.weekdays, remindAt: $0, source: .setup) })
                                    )
                                }
                            }
                        }
                    }

                    FACard {
                        Toggle(isOn: $sundayDifferent) {
                            Text(String(localized: "mealtimes.setup.sunday", defaultValue: "My Sunday is different"))
                                .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        }
                        .tint(FAColor.brand)
                    }
                    .padding(.top, 12)

                    if let saveError {
                        Text(saveError).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4).padding(.top, 10)
                    }
                }
                .padding(.horizontal, FASpacing.md)
                .padding(.bottom, 24)
            }

            VStack(spacing: 8) {
                FAButton(title: String(localized: "mealtimes.setup.save", defaultValue: "Save my times"), isLoading: saving) { Task { await save() } }
                FAButton(title: String(localized: "mealtimes.card.later", defaultValue: "Not now"), style: .tertiary) {
                    dependencies.notifications.markMealSetupOffered()
                    dismiss()
                }
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.vertical, 12)
        }
        .faWall()
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var confirmed = draft
        if !sundayDifferent {
            // One weekend: Sunday takes Saturday's answers.
            for slot in MealSlot.allCases {
                let saturday = confirmed.entry(slot, weekday: 6)
                confirmed.set(slot, weekdays: [7], enabled: saturday.enabled, remindAt: saturday.remindAt, source: .setup)
            }
        }
        confirmed.confirmAll(as: .setup)
        do {
            let service = dependencies.notifications
            try await service.saveMealSchedule(confirmed)
            service.markMealSetupOffered()
            await service.replan(snapshot: nil, wearables: dependencies.wearables)
            dismiss()
        } catch let e as AppError { saveError = e.userMessage } catch { saveError = String(describing: error) }
    }
}
