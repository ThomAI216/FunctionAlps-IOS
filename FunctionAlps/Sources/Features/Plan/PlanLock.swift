import SwiftUI

/// An area of the plan the clinician has not defined yet (owner, 2026-10-02: "when not defined, the area is
/// blurred"): a soft, blurred stand-in of what will be there, and over it what to do about it. Before the first
/// plan that is the call — "Book your call", or the date of the call already booked (`appointments`); inside a
/// published plan it is a quiet line saying the practitioner fills it in. The blurred stand-in carries no words
/// and is hidden from VoiceOver; the overlay is what is read.
struct PlanLockedArea<Placeholder: View>: View {
    enum Reason {
        /// No plan yet: book the first call, or see when it is.
        case awaitingCall(AppointmentRow?)
        /// The plan exists; this part is not written yet.
        case notDefinedYet
        /// No actions yet: pick a foundation action meanwhile.
        case noActions
    }

    let reason: Reason
    @ViewBuilder let placeholder: Placeholder
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            placeholder
                .blur(radius: 7)
                .opacity(0.75)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            overlay
                .padding(14)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var overlay: some View {
        VStack(spacing: 8) {
            switch reason {
            case .awaitingCall(let call?):
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 20, weight: .semibold)).foregroundStyle(FAColor.forest)
                    .accessibilityHidden(true)
                Text(String(localized: "lock.call.booked.title", defaultValue: "Your call is booked"))
                    .font(FATypography.headline).foregroundStyle(FAColor.ink)
                if let start = call.start {
                    Text(start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                        .font(FATypography.display(18, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                        .multilineTextAlignment(.center)
                }
                Text(call.isVideo
                     ? String(localized: "lock.call.booked.video", defaultValue: "By video. Your plan appears here after the call.")
                     : String(localized: "lock.call.booked.message", defaultValue: "Your plan appears here after the call."))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.center)
            case .awaitingCall(nil):
                Image(systemName: "lock").font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.forest)
                    .accessibilityHidden(true)
                Text(String(localized: "lock.call.title", defaultValue: "Your plan comes after your call"))
                    .font(FATypography.headline).foregroundStyle(FAColor.ink).multilineTextAlignment(.center)
                Text(String(localized: "lock.call.message", defaultValue: "Book your call to talk it through with a clinician. Your health plan appears here afterwards."))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { openURL(PlanAccess.bookingURL) } label: {
                    Text(String(localized: "lock.call.book", defaultValue: "Book my call"))
                        .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(FAColor.forest, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            case .notDefinedYet:
                Text(String(localized: "lock.notDefined", defaultValue: "Your practitioner fills this in with you"))
                    .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    .multilineTextAlignment(.center)
            case .noActions:
                Text(String(localized: "lock.actions.title", defaultValue: "Your daily actions appear here"))
                    .font(FATypography.headline).foregroundStyle(FAColor.ink).multilineTextAlignment(.center)
                Text(String(localized: "lock.actions.message", defaultValue: "Meanwhile, you can pick a foundation action to start with."))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary).multilineTextAlignment(.center)
                NavigationLink(value: Route.actionBank) {
                    Text(String(localized: "bank.open", defaultValue: "Choose an action"))
                        .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(FAColor.forest, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: 320)
        .modifier(FAGlassSurface(cornerRadius: 18, inset: true))
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// A wordless stand-in for a plan area: a heading bar and a few lines of different lengths.
struct PlanPlaceholderLines: View {
    var lines = 3
    var chips = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 4).fill(FAColor.ink.opacity(0.22)).frame(width: 140, height: 14)
            ForEach(0..<lines, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4).fill(FAColor.ink.opacity(0.12))
                    .frame(maxWidth: i % 2 == 0 ? .infinity : 220, minHeight: 10, maxHeight: 10)
            }
            if chips {
                HStack(spacing: 6) {
                    ForEach([90, 120, 70], id: \.self) { w in
                        Capsule().fill(FAColor.forestSoft.opacity(0.25)).frame(width: CGFloat(w), height: 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
