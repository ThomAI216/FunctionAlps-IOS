import SwiftUI

/// One supplement's page (mockup `R7_iOSSupplementPageV2`, with the owner's changes of 2026-11-12: "What it does in
/// your body" is the second card, and there is no "What the studies say" card). Blocks, in order: the supplement and
/// why it is in the plan · what it does in the body · how regularly it is taken, with today's switch · how to take it
/// · the brand · who prescribed it · the reminder. A block with nothing to say is not drawn.
struct SupplementPage: View {
    let supplementId: String
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: SupplementPageViewModel?

    var body: some View {
        VStack(spacing: 0) {
            CenteredHeader(title: String(localized: "supp.page.title", defaultValue: "Supplement"), hairline: true)
            if let model {
                content(model)
            } else {
                FALoadingState()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil { model = SupplementPageViewModel(supplementId: supplementId, service: dependencies.supplements, notifications: dependencies.notifications) }
            await model?.load()
            // The reminder line reads the member's reminder times.
            if let member = try? await dependencies.members.currentMember() { await dependencies.notifications.loadPrefs(patientId: member.patientId) }
        }
    }

    @ViewBuilder
    private func content(_ model: SupplementPageViewModel) -> some View {
        switch model.phase {
        case .idle, .loading:
            FALoadingState(message: String(localized: "supp.loading", defaultValue: "Loading your supplements…"))
        case .failed(let message):
            FAErrorState(title: String(localized: "supp.error.title", defaultValue: "Couldn't load your supplements"), message: message) {
                Task { await model.retry() }
            }
        case .loaded:
            if let s = model.supplement {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        header(s, model)
                        bodyCard(s, model)
                        adherenceCard(s, model)
                        howToCard(s, model)
                        brandCard(s, model)
                        prescribedCard(s, model)
                        reminderCard(s, model)
                    }
                    .padding(16)
                    .padding(.bottom, FASpacing.navBarClearance)
                }
                .refreshable { await model.retry() }
            } else {
                FAEmptyState(title: String(localized: "supp.missing.title", defaultValue: "This supplement is no longer in your plan"),
                             message: String(localized: "supp.missing.message", defaultValue: "Your practitioner may have changed your plan."), systemImage: "pills")
            }
        }
    }

    // MARK: Cards

    private func header(_ s: Supplement, _ model: SupplementPageViewModel) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 7) {
                CPLabel(String(localized: "supp.page.label", defaultValue: "Supplement"))
                Text(s.name).font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SupplementLogic.doseLine(s)).font(FATypography.sans(13.5, .semibold, relativeTo: .callout)).foregroundStyle(SupplementPalette.blue)
                if let rhythm = SupplementLogic.rhythmText(s) {
                    Text(rhythm).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
                if !s.isActive {
                    Label(String(localized: "supp.paused", defaultValue: "Paused"), systemImage: "pause.circle")
                        .font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                }
                if let why = model.why(s) {
                    CPLabel(String(localized: "supp.why.label", defaultValue: "Why it's in your plan")).padding(.top, 4)
                    Text(why).font(FATypography.callout).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func bodyCard(_ s: Supplement, _ model: SupplementPageViewModel) -> some View {
        if let effect = model.bodyEffect(s) {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    CPLabel(String(localized: "supp.body.label", defaultValue: "What it does in your body"))
                    if let text = effect.text {
                        Text(text).font(FATypography.callout).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    if !effect.areas.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(effect.areas, id: \.self) { area in
                                Text(area).font(FATypography.sans(12.5, .semibold, relativeTo: .caption))
                                    .foregroundStyle(SupplementPalette.blue)
                                    .padding(.horizontal, 11).padding(.vertical, 4)
                                    .background(SupplementPalette.blueSoft.opacity(0.13), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func adherenceCard(_ s: Supplement, _ model: SupplementPageViewModel) -> some View {
        let toggles = model.toggles(s)
        if s.observance != nil || !toggles.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 10) {
                    CPLabel(String(localized: "supp.adherence.label", defaultValue: "How regularly you take it"))
                    if s.observance != nil { SupplementAdherenceLine(supplement: s, large: true) }
                    if let strip = s.observance?.strip, !strip.isEmpty { SupplementStrip(days: strip) }
                    ForEach(toggles) { toggle in
                        Divider().overlay(ProfilePalette.hairline)
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(toggle.moment.takenLabel).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                Text(toggleStatus(toggle)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                            }
                            Spacer(minLength: 8)
                            Toggle(isOn: Binding(get: { toggle.taken }, set: { value in Task { await model.setTaken(value, moment: toggle.moment) } })) {
                                Text(toggle.moment.takenLabel)
                            }
                            .labelsHidden()
                            .tint(FAColor.brand)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let error = model.tickError {
                        Text(error).font(FATypography.caption).foregroundStyle(ProfilePalette.red)
                    }
                }
            }
        }
    }

    private func toggleStatus(_ toggle: SupplementTick) -> String {
        if toggle.taken {
            if let at = toggle.takenAt { return String(localized: "supp.taken.at", defaultValue: "\(toggle.moment.displayName) · taken at \(Format.time(at))") }
            return String(localized: "supp.taken.done", defaultValue: "\(toggle.moment.displayName) · taken")
        }
        return String(localized: "supp.taken.notYet", defaultValue: "\(toggle.moment.displayName) · not yet")
    }

    @ViewBuilder
    private func howToCard(_ s: Supplement, _ model: SupplementPageViewModel) -> some View {
        let steps = model.howToTake(s)
        if !steps.isEmpty {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    CPLabel(String(localized: "supp.howto.label", defaultValue: "How to take it"))
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(SupplementPalette.blueSoft).frame(width: 6, height: 6).accessibilityHidden(true)
                            Text(step).font(FATypography.sans(13, relativeTo: .footnote)).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func brandCard(_ s: Supplement, _ model: SupplementPageViewModel) -> some View {
        if let b = model.brand(s) {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    CPLabel(String(localized: "supp.brand.label", defaultValue: "Your brand"))
                    if let url = b.imageURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color.clear
                        }
                        .frame(maxWidth: .infinity, maxHeight: 140)
                        .accessibilityHidden(true)
                    }
                    if let label = b.label {
                        Text(label).font(FATypography.display(19, relativeTo: .title3)).foregroundStyle(FAColor.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    if let pack = b.pack {
                        Text(pack).font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(SupplementPalette.blue)
                    }
                    if let price = b.price {
                        Text(price).font(FATypography.sans(13, .semibold, relativeTo: .footnote)).foregroundStyle(FAColor.ink)
                    }
                    if let composition = b.composition {
                        CPLabel(String(localized: "supp.inside.label", defaultValue: "What's inside")).padding(.top, 2)
                        Text(composition).font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let buy = b.buyURL {
                        Link(destination: buy) {
                            HStack(spacing: 8) {
                                Text(String(localized: "supp.buy", defaultValue: "Where to buy")).font(FATypography.sans(14, .semibold, relativeTo: .subheadline))
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).frame(minHeight: FAButton.visualHeight)
                            .background(FAColor.brand, in: Capsule())
                            .frame(minHeight: FAButton.hitHeight)
                            .contentShape(Rectangle())
                        }
                        Text(buyNote(buy, checked: b.checked)).font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(FAColor.inkSecondary)
                    }
                    if let more = b.learnMoreURL {
                        Link(destination: more) {
                            HStack(spacing: 6) {
                                Text(String(localized: "supp.learnMore", defaultValue: "Learn more")).font(FATypography.sans(13, .semibold, relativeTo: .footnote))
                                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                            }
                            .foregroundStyle(FAColor.brand)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
    }

    private func buyNote(_ url: URL, checked: Date?) -> String {
        let shop = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        if let checked {
            let day = checked.formatted(.dateTime.day().month(.abbreviated))
            return String(localized: "supp.buy.noteChecked", defaultValue: "Opens \(shop) in your browser · link checked \(day)")
        }
        return String(localized: "supp.buy.note", defaultValue: "Opens \(shop) in your browser.")
    }

    @ViewBuilder
    private func prescribedCard(_ s: Supplement, _ model: SupplementPageViewModel) -> some View {
        if let p = model.prescribed(s) {
            FACard {
                VStack(alignment: .leading, spacing: 8) {
                    CPLabel(String(localized: "supp.prescribed.label", defaultValue: "Prescribed"))
                    HStack(spacing: 10) {
                        if let name = p.name {
                            Text(String(name.prefix(1)).uppercased())
                                .font(FATypography.sans(13, .bold, relativeTo: .footnote)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(FAColor.brand, in: Circle())
                                .accessibilityHidden(true)
                        }
                        Text(prescribedLine(p)).font(FATypography.callout).foregroundStyle(FAColor.ink)
                    }
                }
            }
        }
    }

    private func prescribedLine(_ p: SupplementPageBlocks.Prescribed) -> String {
        switch (p.name, p.since) {
        case (let name?, let since?):
            String(localized: "supp.prescribed.nameSince", defaultValue: "\(name) · since \(since.formatted(.dateTime.day().month(.abbreviated).year()))")
        case (let name?, nil): name
        case (nil, let since?): String(localized: "supp.prescribed.since", defaultValue: "Since \(since.formatted(.dateTime.day().month(.abbreviated).year()))")
        default: ""
        }
    }

    @ViewBuilder
    private func reminderCard(_ s: Supplement, _ model: SupplementPageViewModel) -> some View {
        if let line = model.reminderLine(s) {
            FACard {
                NavigationLink(value: Route.notifications) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell").font(.system(size: 14, weight: .medium)).foregroundStyle(SupplementPalette.blue)
                            .frame(width: 32, height: 32).background(SupplementPalette.blueSoft.opacity(0.16), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                            Text(String(localized: "supp.reminder.sub", defaultValue: "Only on days it is due")).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FAColor.inkMuted).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
