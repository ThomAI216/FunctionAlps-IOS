import SwiftUI
import UIKit
import UserNotifications

/// One question of a Foundation Track page, drawn by its kind. The words are the practice's (`track_question`,
/// rule 6); the app adds the controls, "Optional", and the "from your earlier answers" chip.
struct TrackQuestionView: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel
    let onUpdateBaseline: () -> Void
    /// "Not now" on the Apple Health and reminders pages: recorded, then on to the next page.
    let onSkip: () -> Void

    var body: some View {
        switch question.kind {
        case .info?:
            TrackInfoBlock(question: question, model: model)
        case .connectHealth?:
            TrackHealthBlock(question: question, model: model, onSkip: onSkip)
        case .enableNotifications?:
            TrackRemindersBlock(question: question, model: model, onSkip: onSkip)
        default:
            VStack(alignment: .leading, spacing: 12) {
                header
                input
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let source = model.chip(question) {
                HStack(spacing: 5) {
                    Image(systemName: source == .health ? "heart" : "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(source == .health
                         ? String(localized: "track.chip.health", defaultValue: "From Apple Health")
                         : String(localized: "track.chip.earlier", defaultValue: "From your earlier answers"))
                        .font(FATypography.label)
                }
                .foregroundStyle(FAColor.forestDark)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(FAColor.forestSoft.opacity(0.18), in: Capsule())
            }
            Text(model.prompt(question))
                .font(FATypography.sans(17, .semibold, relativeTo: .headline)).foregroundStyle(FAColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let help = model.help(question) {
                Text(help).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        switch question.kind {
        case .single?:
            TrackChoices(options: model.options(question), model: model, isOn: { model.isChosen($0, in: question) }) { model.select($0, in: question) }
        case .multi?:
            TrackMultiChoice(question: question, model: model)
        case .text?:
            TrackTextInput(question: question, model: model)
        case .number?:
            TrackNumberInput(question: question, model: model)
        case .time?:
            TrackTimeInput(question: question, model: model)
        case .slider?:
            TrackSliderInput(question: question, model: model)
        case .confirm?:
            TrackConfirmInput(question: question, model: model, onUpdate: onUpdateBaseline)
        default:
            EmptyView()
        }
    }
}

// MARK: - Choices

/// Large tappable pills; chosen = filled AND a check mark (never colour alone).
private struct TrackChoices: View {
    let options: [TrackOption]
    let model: TrackQuestionnaireModel
    var enabled: (String) -> Bool = { _ in true }
    let isOn: (String) -> Bool
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                let on = isOn(option.value)
                Button { onTap(option.value) } label: {
                    HStack(spacing: 6) {
                        if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).accessibilityHidden(true) }
                        Text(model.label(option)).font(FATypography.sans(14, on ? .semibold : .medium, relativeTo: .subheadline))
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(on ? Color.white : FAColor.ink)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(on ? FAColor.forest : Color.white.opacity(0.7), in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? FAColor.forest : FAColor.forestSoft.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!on && !enabled(option.value))
                .opacity(!on && !enabled(option.value) ? 0.45 : 1)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Multiple choice: honours `max_select`; an option with free text opens a field stored as `<key>_other`.
private struct TrackMultiChoice: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel

    var body: some View {
        let options = model.options(question)
        let chosen = model.value(question.key)?.scalarTexts ?? []
        let full = question.maxSelect.map { $0 > 0 && chosen.count >= $0 } ?? false
        VStack(alignment: .leading, spacing: 10) {
            TrackChoices(options: options, model: model, enabled: { _ in !full },
                         isOn: { model.isChosen($0, in: question) }) { model.toggle($0, in: question) }
            if let max = question.maxSelect, max > 0 {
                Text(String(localized: "track.multi.count", defaultValue: "\(chosen.count) of \(max) chosen"))
                    .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            }
            if let free = options.first(where: \.freeText), chosen.contains(free.value) {
                TrackField(text: Binding(
                    get: { model.value(question.key + "_other")?.stringValue ?? "" },
                    set: { model.set(question.key + "_other", $0.isEmpty ? nil : .string($0)) }
                ), placeholder: String(localized: "track.other.placeholder", defaultValue: "Tell us"), multiline: false)
            }
        }
    }
}

// MARK: - Text, number, time, slider

/// The see-through field the flow uses (a hairline glass pane, Dynamic Type).
private struct TrackField: View {
    @Binding var text: String
    let placeholder: String
    var multiline = true
    var keyboard: UIKeyboardType = .default

    var body: some View {
        Group {
            if multiline {
                TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...8)
            } else {
                TextField(placeholder, text: $text).keyboardType(keyboard)
            }
        }
        .font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink)
        .padding(12)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.forestSoft.opacity(0.3), lineWidth: 1))
    }
}

private struct TrackTextInput: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel

    var body: some View {
        TrackField(text: Binding(
            get: { model.value(question.key)?.stringValue ?? "" },
            set: { model.set(question.key, $0.isEmpty ? nil : .string($0)) }
        ), placeholder: question.required
            ? String(localized: "track.text.placeholder", defaultValue: "Your answer")
            : String(localized: "track.text.optional", defaultValue: "Optional"))
    }
}

/// A number with its unit, stored as a number (never text).
private struct TrackNumberInput: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            TrackField(text: $text, placeholder: "0", multiline: false, keyboard: .decimalPad)
                .frame(maxWidth: 160)
            if let unit = question.unit {
                Text(unit).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.inkSecondary)
            }
        }
        .onAppear {
            if let v = model.value(question.key)?.doubleValue { text = v == v.rounded() ? String(Int(v)) : String(v) }
        }
        .onChange(of: text) { _, raw in
            let normalized = raw.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            guard let v = Double(normalized) else { model.set(question.key, nil); return }
            let clamped = min(max(v, question.minValue ?? -.greatestFiniteMagnitude), question.maxValue ?? .greatestFiniteMagnitude)
            model.set(question.key, clamped == clamped.rounded() ? .int(Int(clamped)) : .number(clamped))
        }
    }
}

/// Hours and minutes on a wheel, stored as `HH:mm`.
private struct TrackTimeInput: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel

    var body: some View {
        DatePicker(String(localized: "track.time.label", defaultValue: "Time"), selection: Binding(
            get: {
                let m = TrackLogic.minutes(model.value(question.key)?.stringValue) ?? TrackLogic.minutes(TrackLogic.defaultTime(for: question.key)) ?? 12 * 60
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current
                model.set(question.key, .string(TrackLogic.hhmm(c.component(.hour, from: date) * 60 + c.component(.minute, from: date))))
            }
        ), displayedComponents: .hourAndMinute)
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}

/// A 0–10 style slider; the value is shown in words next to it, and nothing is recorded until it is moved.
private struct TrackSliderInput: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel

    var body: some View {
        let low = question.minValue ?? 0
        let high = max(question.maxValue ?? 10, low + 1)
        let step = question.step.flatMap { $0 > 0 ? $0 : nil } ?? 1
        let current = model.value(question.key)?.doubleValue
        VStack(alignment: .leading, spacing: 6) {
            Text(current.map { String(localized: "track.slider.value", defaultValue: "\(format($0)) / \(format(high))") }
                 ?? String(localized: "track.slider.unset", defaultValue: "Move the slider"))
                .font(FATypography.sans(15, .semibold, relativeTo: .body))
                .foregroundStyle(current == nil ? FAColor.inkSecondary : FAColor.ink)
            Slider(value: Binding(
                get: { current ?? (low + high) / 2 },
                set: { v in
                    let snapped = (v / step).rounded() * step
                    model.set(question.key, step == step.rounded() && snapped == snapped.rounded() ? .int(Int(snapped)) : .number(snapped))
                }
            ), in: low...high, step: step) {
                Text(model.prompt(question))
            } minimumValueLabel: {
                Text(format(low)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            } maximumValueLabel: {
                Text(format(high)).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            }
            .tint(FAColor.forestSoft)
            .opacity(current == nil ? 0.6 : 1)
        }
    }

    private func format(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

// MARK: - Confirm (the baseline)

/// "From your FunctionAlps record: … Still right?" — Yes, or Update (the baseline editor, then back here).
private struct TrackConfirmInput: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel
    let onUpdate: () -> Void

    var body: some View {
        let options = model.options(question)
        VStack(alignment: .leading, spacing: 10) {
            if let line = model.baselineLine(question) {
                Text(line).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(FAGlassSurface(cornerRadius: 14, inset: true))
            }
            TrackChoices(options: options, model: model, isOn: { model.isChosen($0, in: question) }) { value in
                model.set(question.key, .string(value))
                if value == "update" { onUpdate() }
            }
        }
    }
}

// MARK: - Info, Apple Health, reminders

private struct TrackInfoBlock: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch question.key {
            case "week1_recap":
                title
                let lines = model.weekOneRecap
                if lines.isEmpty {
                    Text(String(localized: "track.recap.empty", defaultValue: "Your answers from this week will show here."))
                        .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(FAGlassSurface(cornerRadius: 16, inset: true))
                }
            case "two_weeks_compare":
                title
                Text(String(localized: "track.compare.soon", defaultValue: "Your before/after comparison is coming soon."))
                    .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(FAGlassSurface(cornerRadius: 16, inset: true))
            default:
                Text(model.prompt(question)).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(FAGlassSurface(cornerRadius: 16, inset: true))
                if let help = model.help(question) {
                    Text(help).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
        }
    }

    private var title: some View {
        Text(model.prompt(question)).font(FATypography.display(22, relativeTo: .title2)).foregroundStyle(FAColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A page with an icon, the practice's title and line, one action, and "Not now".
private struct TrackPermissionBlock<Action: View>: View {
    let symbol: String
    let title: String
    let body_: String?
    @ViewBuilder let action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                .frame(width: 52, height: 52)
                .background(FAColor.forestSoft.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(FATypography.display(24, relativeTo: .title2)).foregroundStyle(FAColor.ink)
                .accessibilityAddTraits(.isHeader)
            if let body_ {
                Text(body_).font(FATypography.sans(15, relativeTo: .body)).foregroundStyle(FAColor.ink2).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action
        }
    }
}

private struct TrackDoneLine: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.forest)
    }
}

private struct TrackNotNow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(localized: "track.notNow", defaultValue: "Not now"))
                .font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TrackHealthBlock: View {
    let question: TrackQuestion
    let model: TrackQuestionnaireModel
    let onSkip: () -> Void
    @State private var busy = false

    var body: some View {
        TrackPermissionBlock(symbol: "heart.text.square", title: model.prompt(question), body_: model.help(question)) {
            if model.healthConnected {
                TrackDoneLine(text: String(localized: "track.health.connected", defaultValue: "Apple Health is connected"))
            } else if !WearableService.isAvailable {
                Text(String(localized: "track.health.unavailable", defaultValue: "Apple Health isn't available on this device."))
                    .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                TrackNotNow { model.set(question.key, .string("unavailable")); onSkip() }
            } else {
                FAButton(title: String(localized: "track.health.connect", defaultValue: "Connect Apple Health"), isLoading: busy) {
                    busy = true
                    Task {
                        await model.connectHealth(question)
                        busy = false
                    }
                }
                if model.healthFailed {
                    Text(String(localized: "wearables.syncFailed", defaultValue: "Apple Health couldn't be read just now. Try again in a moment."))
                        .font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
                TrackNotNow { model.set(question.key, .string("skipped")); onSkip() }
            }
        }
    }
}

private struct TrackRemindersBlock: View {
    @Environment(\.openURL) private var openURL
    let question: TrackQuestion
    let model: TrackQuestionnaireModel
    let onSkip: () -> Void
    @State private var busy = false

    var body: some View {
        TrackPermissionBlock(symbol: "bell.badge", title: model.prompt(question), body_: model.help(question)) {
            switch model.remindersStatus {
            case .authorized, .provisional, .ephemeral:
                TrackDoneLine(text: String(localized: "track.reminders.on", defaultValue: "Your reminders are on"))
            case .denied:
                Text(String(localized: "track.reminders.denied", defaultValue: "Notifications are off for FunctionAlps in your iPhone's Settings."))
                    .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FAButton(title: String(localized: "track.reminders.settings", defaultValue: "Open Settings"), style: .secondary) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                TrackNotNow { model.set(question.key, .string("declined")); onSkip() }
            default:
                FAButton(title: String(localized: "track.reminders.enable", defaultValue: "Turn on reminders"), isLoading: busy) {
                    busy = true
                    Task {
                        await model.enableReminders(question)
                        busy = false
                    }
                }
                TrackNotNow { model.set(question.key, .string("skipped")); onSkip() }
            }
        }
    }
}
