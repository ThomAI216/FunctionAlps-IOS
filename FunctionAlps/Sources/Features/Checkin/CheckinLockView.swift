import SwiftUI

/// Lock after save (owner-validated 2026-11-12): while a check-in is saved, everything inside is read-only. A tap on it asks
/// "Change your check-in for <weekday d MMM>?" — Change unlocks it for editing, Cancel leaves it as it is.
private struct CheckinLockModifier: ViewModifier {
    let isLocked: Bool
    /// The day the check-in is for, `YYYY-MM-DD` — named in the question.
    let day: String
    let onChange: () -> Void
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .disabled(isLocked)
            .overlay {
                if isLocked {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { asking = true }
                        .accessibilityElement()
                        .accessibilityLabel(CheckinLockText.note(day: day))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(String(localized: "checkin.lock.hint", defaultValue: "Asks before it lets you change your answers"))
                        .accessibilityAction { asking = true }
                }
            }
            #if DEBUG
            // The `checkin-locked` screenshot: the question open over the saved check-in, as a tap would raise it.
            .task(id: isLocked) {
                guard isLocked, Showcase.screen == .checkinLocked else { return }
                try? await Task.sleep(for: .seconds(2))
                asking = true
            }
            #endif
            .alert(CheckinLockText.question(day: day), isPresented: $asking) {
                Button(String(localized: "checkin.lock.change", defaultValue: "Change")) { onChange() }
                Button(String(localized: "action.cancel", defaultValue: "Cancel"), role: .cancel) {}
            }
    }
}

enum CheckinLockText {
    static func dayText(_ day: String) -> String {
        CheckinDayLabel.text(forDay: day) ?? day
    }

    /// "Change your check-in for Thursday 12 Nov?"
    static func question(day: String) -> String {
        let label = dayText(day)
        return String(localized: "checkin.lock.title", defaultValue: "Change your check-in for \(label)?")
    }

    /// "Saved for Thursday 12 Nov · tap anything to change it"
    static func note(day: String) -> String {
        let label = dayText(day)
        return String(localized: "checkin.lock.note", defaultValue: "Saved for \(label) · tap anything to change it")
    }
}

extension View {
    /// Read-only while `isLocked`; a tap asks before `onChange` unlocks it.
    func checkinLock(isLocked: Bool, day: String, onChange: @escaping () -> Void) -> some View {
        modifier(CheckinLockModifier(isLocked: isLocked, day: day, onChange: onChange))
    }
}

/// The small line above a locked check-in.
struct CheckinLockedNote: View {
    let day: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
            Text(CheckinLockText.note(day: day)).font(FATypography.caption)
        }
        .foregroundStyle(FAColor.inkSecondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FAColor.forest.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
