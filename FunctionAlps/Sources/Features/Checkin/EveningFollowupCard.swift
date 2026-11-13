import SwiftUI

/// After a hard morning (a short night, or a flat / depleted feeling), the DAILY check-in opens with one small card: how was
/// the rest of the day — better, about the same, harder — and what made the difference. The answer is stored on today's
/// `patient_day_feelings` row (`evening_followup`, `evening_pills`) as it is given; the check-in's own Save is separate.
/// Whether it is asked at all is the focus cell's (`hardMorning`); the question and the pills are the owner's wording.
struct EveningFollowupCard: View {
    @Environment(AppDependencies.self) private var dependencies
    let slot: MomentSlot
    /// A missed day being caught up is over: no follow-up there.
    let catchingUp: Bool
    @State private var model: EveningFollowupModel?

    private var asked: Bool {
        EveningFollowupLogic.isAsked(cell: dependencies.focus.focus?.cell, slot: slot, catchingUp: catchingUp)
    }

    var body: some View {
        // A real container: a modifier on an empty Group never runs, and the card starts out empty.
        VStack(spacing: 0) {
            if asked, let model { card(model) }
        }
        .task {
            // The check-in can be opened without Home (a reminder): make sure today's focus is read.
            guard slot == .evening, !catchingUp else { return }
            await dependencies.focus.load()
            guard EveningFollowupLogic.isAsked(cell: dependencies.focus.focus?.cell, slot: slot, catchingUp: catchingUp), model == nil else { return }
            let m = EveningFollowupModel(backend: dependencies.backend, members: dependencies.members, day: dependencies.checkins.today)
            model = m
            await m.load()
        }
    }

    private func card(_ model: EveningFollowupModel) -> some View {
        let options = EveningFollowupLogic.options(plan: dependencies.habits.plan, focus: dependencies.focus.focus, saved: model.followup.pills)
        return FACard {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "followup.title", defaultValue: "This morning was hard. How was the rest of your day?"))
                    .font(FATypography.headline).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(EveningFollowup.Choice.allCases.reversed(), id: \.self) { choice in
                        choiceButton(choice, model: model)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "followup.pills.title", defaultValue: "What made the difference?"))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    FlowLayout(spacing: 7) {
                        ForEach(options) { option in
                            PillButton(label: option.label, hue: FAColor.forestSoft, on: model.followup.pills.contains(option.key)) {
                                model.toggle(option.key)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                if model.saveFailed {
                    Text(String(localized: "followup.saveFailed", defaultValue: "Couldn't save this · tap again to retry."))
                        .font(FATypography.caption).foregroundStyle(FAColor.danger)
                }
            }
        }
        .id("showcase.followup")
    }

    private func label(_ choice: EveningFollowup.Choice) -> String {
        switch choice {
        case .better: String(localized: "followup.better", defaultValue: "Better")
        case .same: String(localized: "followup.same", defaultValue: "About the same")
        case .harder: String(localized: "followup.harder", defaultValue: "Harder")
        }
    }

    private func choiceButton(_ choice: EveningFollowup.Choice, model: EveningFollowupModel) -> some View {
        let on = model.followup.choice == choice
        return Button { model.choose(choice) } label: {
            Text(label(choice))
                .font(FATypography.sans(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(on ? Color.white : FAColor.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? FAColor.forest : Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The follow-up's state: read once, written as it changes. Writes are serialised so two quick taps never land out of order, and
/// a failed write says so and keeps the answer on screen.
@MainActor
@Observable
final class EveningFollowupModel {
    private(set) var followup = EveningFollowup()
    private(set) var saveFailed = false

    private let backend: any FunctionAlpsBackend
    private let members: MemberService
    private let day: String
    private var patientId: String?
    private var inflight: Task<Void, Never>?

    init(backend: any FunctionAlpsBackend, members: MemberService, day: String) {
        self.backend = backend
        self.members = members
        self.day = day
    }

    func load() async {
        guard let member = try? await members.currentMember() else { return }
        patientId = member.patientId
        // Fail-soft: a database without the columns, or a read that fails, is "nothing saved yet".
        if let saved = try? await backend.eveningFollowup(patientId: member.patientId, day: day) { followup = saved }
    }

    func choose(_ choice: EveningFollowup.Choice) {
        followup.choice = followup.choice == choice ? nil : choice
        save()
    }

    func toggle(_ key: String) {
        followup.pills = EveningFollowupLogic.toggled(followup.pills, key)
        save()
    }

    private func save() {
        guard let patientId else { return }
        let snapshot = followup, previous = inflight
        saveFailed = false
        let backend = self.backend, day = self.day
        inflight = Task { [weak self] in
            await previous?.value
            do { try await backend.saveEveningFollowup(patientId: patientId, day: day, followup: snapshot) }
            catch { self?.saveFailed = true }
        }
    }
}
