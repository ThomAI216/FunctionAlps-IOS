import SwiftUI

/// Settings → Notifications → Meal times. The member's own schedule (`member_meal_schedule`): which meals get
/// a reminder and when — by Weekdays · Saturday · Sunday, or day by day. Every change saves and re-plans.
struct MealScheduleView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var state: Loadable<MealSchedule> = .loading
    @State private var schedule: MealSchedule = .defaults
    @State private var perDay = false
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?

    private var service: NotificationService { dependencies.notifications }

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "mealtimes.title", defaultValue: "Meal times"))
            switch state {
            case .loading:
                FALoadingState().frame(maxHeight: .infinity)
            case .failed(let error):
                FAErrorState(title: String(localized: "mealtimes.error.title", defaultValue: "Couldn't load your meal times"), message: error.userMessage) {
                    Task { await load() }
                }
                .frame(maxHeight: .infinity)
            case .empty:
                FAEmptyState(title: String(localized: "mealtimes.empty.title", defaultValue: "No meal times yet"),
                             message: String(localized: "mealtimes.empty.message", defaultValue: "Your meal times appear here once your FunctionAlps profile is linked."),
                             systemImage: "clock")
                    .frame(maxHeight: .infinity)
            case .loaded:
                editor
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: schedule) { _, new in save(new) }
    }

    private func load() async {
        state = .loading
        if let member = try? await dependencies.members.currentMember() { await service.loadPrefs(patientId: member.patientId, force: true) }
        do {
            // Loading the preferences reads the schedule too; ask again only if that read did not land.
            let loaded: MealSchedule
            if let known = service.mealSchedule { loaded = known } else { loaded = try await service.loadMealSchedule() }
            schedule = loaded
            perDay = !MealSchedule.Group.allCases.allSatisfy { group in MealSlot.allCases.allSatisfy { loaded.isUniform($0, weekdays: group.weekdays) } }
            state = .loaded(loaded)
        } catch AppError.notFound {
            state = .empty
        } catch let e as AppError {
            state = .failed(e)
        } catch {
            state = .failed(.unknown(detail: String(describing: error)))
        }
    }

    /// Debounced: a time picker settles before anything is written; only changed rows travel.
    private func save(_ new: MealSchedule) {
        guard state.value != nil, new != service.mealSchedule else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                try await service.saveMealSchedule(new)
                saveError = nil
                await service.replan(snapshot: nil, wearables: dependencies.wearables)
            } catch let e as AppError { saveError = e.userMessage } catch { saveError = String(describing: error) }
        }
    }

    // MARK: Editor

    private var editor: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "mealtimes.intro", defaultValue: "A reminder comes at each time you switch on — only while that meal isn't logged yet. Switch off any meal you don't usually have."))
                    .font(FATypography.sans(13, relativeTo: .callout)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                    .padding(.top, 6).padding(.bottom, 12)

                if !service.prefs.mealRemindersEnabled {
                    FACard {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "bell.slash").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.muted).accessibilityHidden(true)
                            Text(String(localized: "mealtimes.off", defaultValue: "Meal reminders are switched off. Turn them on in Notifications to use these times."))
                                .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.ink).lineSpacing(4)
                        }
                    }
                    .padding(.bottom, 4)
                }

                FACard {
                    Toggle(isOn: $perDay) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "mealtimes.perDay", defaultValue: "Set each day separately"))
                                .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                            Text(String(localized: "mealtimes.perDay.sub", defaultValue: "For a day that runs differently — a late Friday, a Sunday brunch."))
                                .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(3)
                        }
                    }
                    .tint(FAColor.brand)
                }

                if perDay {
                    ForEach(1...7, id: \.self) { day in section(Self.dayName(day), weekdays: [day]) }
                } else {
                    ForEach(MealSchedule.Group.allCases, id: \.self) { group in section(Self.groupName(group), weekdays: group.weekdays) }
                }

                if let saveError {
                    Text(saveError).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.red).lineSpacing(4).padding(.top, 10)
                }

                Text(String(localized: "mealtimes.footer", defaultValue: "Reminders never come inside your quiet hours, and never say anything about what you ate."))
                    .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 18)
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
    }

    private func section(_ title: String, weekdays: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(title: title)
            FACard {
                VStack(spacing: 12) {
                    ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { index, slot in
                        if index > 0 { Divider().overlay(ProfilePalette.hairline) }
                        MealSlotRow(slot: slot,
                                    enabled: enabledBinding(slot, weekdays),
                                    time: timeBinding(slot, weekdays),
                                    caption: caption(slot, weekdays))
                    }
                }
            }
        }
    }

    private func enabledBinding(_ slot: MealSlot, _ weekdays: [Int]) -> Binding<Bool> {
        Binding(get: { schedule.entry(slot, weekday: weekdays[0]).enabled },
                set: { schedule.set(slot, weekdays: weekdays, enabled: $0) })
    }

    private func timeBinding(_ slot: MealSlot, _ weekdays: [Int]) -> Binding<String> {
        Binding(get: { schedule.entry(slot, weekday: weekdays[0]).remindAt },
                set: { schedule.set(slot, weekdays: weekdays, remindAt: $0) })
    }

    private func caption(_ slot: MealSlot, _ weekdays: [Int]) -> String? {
        if !schedule.isUniform(slot, weekdays: weekdays) {
            return String(localized: "mealtimes.varies", defaultValue: "Varies by day — set each day separately to see them")
        }
        return MealSlotRow.sourceCaption(schedule.entry(slot, weekday: weekdays[0]).source)
    }

    // MARK: Names

    /// ISO weekday → the member's own word for it ("Monday", "lundi" → "Lundi").
    static func dayName(_ isoWeekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols    // index 0 = Sunday
        guard symbols.count == 7 else { return "\(isoWeekday)" }
        return symbols[isoWeekday % 7].capitalized(with: .current)
    }

    static func groupName(_ group: MealSchedule.Group) -> String {
        switch group {
        case .weekdays: String(localized: "mealtimes.group.weekdays", defaultValue: "Weekdays")
        case .saturday: dayName(6)
        case .sunday: dayName(7)
        }
    }
}

/// One meal: the switch, and its time when on. Shared by the editor and the first-run setup.
struct MealSlotRow: View {
    let slot: MealSlot
    @Binding var enabled: Bool
    @Binding var time: String
    var caption: String?

    var body: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.localizedName).font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    if let caption {
                        Text(caption).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(3)
                    }
                }
            }
            .tint(FAColor.brand)
            if enabled {
                HStack {
                    Text(String(localized: "notif.at", defaultValue: "At")).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                    Spacer()
                    DatePicker("", selection: Self.date($time), displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.compact).tint(FAColor.brand)
                        .accessibilityLabel(String(localized: "mealtimes.time.a11y", defaultValue: "\(slot.localizedName) reminder time"))
                }
            }
        }
    }

    /// Why a row holds the value it does, when the member did not pick it themselves.
    static func sourceCaption(_ source: MealScheduleEntry.Source) -> String? {
        switch source {
        case .intake: String(localized: "mealtimes.source.intake", defaultValue: "From your intake answers")
        case .profile: String(localized: "mealtimes.source.profile", defaultValue: "From your nutrition profile")
        case .questionnaire: String(localized: "mealtimes.source.questionnaire", defaultValue: "From your questionnaire")
        case .default, .setup, .member, .learned, .pillarObservation: nil
        }
    }

    /// `HH:mm` ⇄ a Date on today's calendar (only the clock part matters).
    static func date(_ text: Binding<String>) -> Binding<Date> {
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
