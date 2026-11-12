import SwiftUI

/// The check-in. TWO are asked for: the MORNING (`MorningCheckinView`: last night, how you feel for the day, the rest of
/// the day on request) and the DAILY one, the evening slot (last night, energy, focus, mood, calm, and the whole digestion
/// read) — this screen. Before 14:00 the member is offered the morning, from 14:00 the daily one (`MomentSlot.current`).
/// A legacy midday row opened from a deep link still renders here.
struct CheckinMomentView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let slot: MomentSlot
    @State private var model: CheckinMomentViewModel?

    var body: some View {
        if slot == .morning {
            MorningCheckinView()
        } else {
            momentScreen
        }
    }

    private var momentScreen: some View {
        ZStack {
            if let model {
                CheckinMomentScreen(model: model) {
                    // Saved: today's reminder for this moment is no longer needed; first save is the moment to ask for permission.
                    let notifications = dependencies.notifications
                    notifications.momentDone(slot, day: dependencies.checkins.today)
                    Task { await notifications.askIfNeeded() }
                    dismiss()
                }
            }
        }
        .faWall()
        .navigationTitle(slot.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                let m = CheckinMomentViewModel(slot: slot, checkins: dependencies.checkins, members: dependencies.members, auth: dependencies.auth,
                                               gut: dependencies.gut, wearables: dependencies.wearables)
                model = m
                await m.prefill()
            }
        }
    }
}

private struct CheckinMomentScreen: View {
    @Bindable var model: CheckinMomentViewModel
    let onSaved: () -> Void

    /// The evening cannot save before its digestion has loaded, or a blank answer set would sit on
    /// top of what was already written today.
    private var canSave: Bool { model.gut.map(\.loaded) ?? true }

    private var dayKey: String { model.day ?? dependencies.checkins.today }
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: FASpacing.md) {
                VStack(alignment: .leading, spacing: FASpacing.xs) {
                    Text(model.greeting).font(FATypography.largeTitle).foregroundStyle(FAColor.ink)
                    Text(model.intro).font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                }
                .padding(.top, FASpacing.sm)

                if model.lock.isLocked { CheckinLockedNote(day: dayKey) }

                VStack(alignment: .leading, spacing: FASpacing.md) {
                    CheckinSectionsView(model: model)
                }
                .checkinLock(isLocked: model.lock.isLocked, day: dayKey) { model.lock.unlock() }

                if model.nothingAnswered {
                    FACard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "checkin.nothingAnswered", defaultValue: "Nothing is answered yet"))
                                .font(FATypography.headline).foregroundStyle(FAColor.ink)
                            Text(String(localized: "checkin.nothingAnswered.hint", defaultValue: "Move at least one slider or pick an answer, then tap Save."))
                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        }
                    }
                }

                if let error = model.saveError {
                    CheckinSaveErrorCard(error: error)
                }

                FAButton(title: model.isSaving ? String(localized: "action.saving", defaultValue: "Saving…") : String(localized: "action.save", defaultValue: "Save"),
                         isLoading: model.isSaving, isEnabled: canSave && !model.lock.isLocked) {
                    Task { if await model.save() { onSaved() } }
                }
            }
            .padding(.horizontal, FASpacing.md)
            .padding(.bottom, FASpacing.navBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
        #if DEBUG
        .task { await Showcase.scroll(proxy, to: "showcase.energy", on: .checkin) }
        .task { await Showcase.scroll(proxy, to: "showcase.mood", on: .checkinMood) }
        .task { await Showcase.scroll(proxy, to: "showcase.stool", on: .checkinStool) }
        .task { await Showcase.scroll(proxy, to: "showcase.stool", on: .bristolChart) }
        .task { await Showcase.scroll(proxy, to: "showcase.flags", on: .checkinNote, anchor: .center) }
        #endif
        }
    }
}

/// "Couldn't save this moment" with the way out, shared by the daily and the morning screens.
struct CheckinSaveErrorCard: View {
    let error: String

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "checkin.saveFailed", defaultValue: "Couldn't save this moment"))
                    .font(FATypography.headline).foregroundStyle(FAColor.danger)
                Text(String(localized: "checkin.saveFailed.hint", defaultValue: "Your answers are still here · tap Save to try again."))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                if BuildInfo.showsTechnicalDetails {
                    Text(error).font(FATypography.caption).foregroundStyle(FAColor.inkMuted)
                }
            }
        }
    }
}

/// The gut check-in, inside the evening reflection: comfort, stool and food reactions, the red flags,
/// and the one note that travels with both the moment and the day's digestion detail.
struct DigestionSections: View {
    @Bindable var model: GutCheckinViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: FASpacing.md) {
            ForEach(GutSchema.dimensions) { spec in
                GutDimensionCard(spec: spec, answers: binding(spec.key), ratedMeals: spec.key == .reactions ? model.ratedMeals : [])
                    .id("showcase.\(spec.key.rawValue)")
            }
            GutRedFlagsCard(flags: $model.redFlags)
                .id("showcase.flags")
            noteBlock
        }
    }

    private func binding(_ key: GutDimKey) -> Binding<GutAnswers> {
        Binding(get: { model.answers[key] ?? .empty }, set: { model.answers[key] = $0 })
    }

    private var noteBlock: some View {
        VoiceNoteBlock(
            addTitle: String(localized: "checkin.note.add", defaultValue: "Add a note about your day (optional)"),
            placeholder: String(localized: "checkin.note.placeholder", defaultValue: "Anything worth remembering about today — meals, symptoms, stress, timing."),
            text: $model.notes, open: $model.notesOpen
        )
    }
}
