import SwiftUI

/// "Supplements today" on Home, under the meal and check-in squares (mockup `iOSHome`): one row per supplement and
/// moment due today, with a "Taken" switch. The moment the clock is in is highlighted (morning until 11:00, midday
/// until 15:00, evening until 21:00, then the night). A supplement not due today is not shown; no supplements due
/// means no card.
///
/// States (rule 5): while the first read is in flight and when nothing is due the card holds no place (most members
/// have no supplements — a skeleton that vanishes on every launch would shove Home around for nothing); a failed
/// read leaves Home as it was — the Plan's list and each supplement's page carry the error and its retry. Reminders
/// are on by default: the first time supplements are shown the phone's notification permission is explained once,
/// then asked.
struct HomeSupplementsCard: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var explaining = false
    /// The permission state is only trusted once it has been read (it starts "not determined").
    @State private var authorizationRead = false

    var body: some View {
        let service = dependencies.supplements
        let rows = service.rows()
        Group {
            if !rows.isEmpty {
                FACard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(localized: "supp.home.title", defaultValue: "Supplements today"))
                                .font(FATypography.headline).foregroundStyle(FAColor.ink)
                            Spacer(minLength: 4)
                            Text(SupplementLogic.progressText(rows))
                                .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        }
                        ForEach(rows) { row in
                            rowView(row, service: service)
                        }
                        if let error = service.tickError {
                            Text(error).font(FATypography.caption).foregroundStyle(ProfilePalette.red)
                        }
                    }
                }
            }
        }
        .task {
            await dependencies.notifications.refreshAuthorization()
            authorizationRead = true
        }
        .onChange(of: authorizationRead && service.shouldExplainReminders, initial: true) { _, should in
            if should { explaining = true }
        }
        .alert(String(localized: "supp.explain.title", defaultValue: "Remind you to take them?"), isPresented: $explaining) {
            Button(String(localized: "supp.explain.yes", defaultValue: "Turn on reminders")) { Task { await service.enableReminders() } }
            Button(String(localized: "supp.explain.no", defaultValue: "Not now"), role: .cancel) { service.markRemindersExplained() }
        } message: {
            Text(String(localized: "supp.explain.body", defaultValue: "One gentle reminder per moment, only on days something is due. Never during your quiet hours."))
        }
    }

    private func rowView(_ row: SupplementLogic.Row, service: SupplementService) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.supplement(row.supplementId)) {
                HStack(spacing: 10) {
                    Text(row.moment.displayName)
                        .font(FATypography.label).foregroundStyle(row.isCurrent ? FAColor.forestDark : FAColor.inkSecondary)
                        .frame(width: 58, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).font(FATypography.sans(13.5, .semibold, relativeTo: .callout)).foregroundStyle(FAColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let dose = row.dose {
                            Text(dose).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            SupplementTakenButton(taken: row.taken, name: row.name) {
                Task { await service.setTaken(!row.taken, supplementId: row.supplementId, moment: row.moment) }
            }
        }
        .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 2)
        .background {
            if row.isCurrent {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FAColor.forestSoft.opacity(0.12))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.35), lineWidth: 1) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(row.isCurrent ? String(localized: "supp.a11y.now", defaultValue: "This moment is now") : "")
    }
}
