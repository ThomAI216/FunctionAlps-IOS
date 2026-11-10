import SwiftUI

/// The day's note: a "+" row that opens a field, and beside the field a microphone — tap, just talk, tap again,
/// and the words land in the note (owner, 2026-11-10). The voice goes to `transcribe-audio`, the sovereign
/// Whisper, exactly like a meal described by voice; nothing is kept but the words the member then saves.
struct VoiceNoteBlock: View {
    let addTitle: String
    let placeholder: String
    @Binding var text: String
    @Binding var open: Bool

    @Environment(AppDependencies.self) private var dependencies
    @State private var dictation: SpeechDictation?
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    Text(open ? String(localized: "gut.notes.hide", defaultValue: "Hide note") : addTitle)
                        .font(FATypography.sans(14, .semibold, relativeTo: .body)).foregroundStyle(FAColor.inkSecondary)
                    Spacer()
                    if !open {
                        Image(systemName: "mic").font(.system(size: 13, weight: .semibold)).foregroundStyle(FAColor.inkSecondary).accessibilityHidden(true)
                    }
                    Text(open ? "−" : "+").font(.system(size: 18, weight: .medium)).foregroundStyle(FAColor.inkSecondary)
                }
                .padding(.vertical, 13).padding(.horizontal, 18)
                .contentShape(Rectangle())
                .modifier(FAGlassSurface(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .font(FATypography.sans(14.5, relativeTo: .body)).foregroundStyle(FAColor.ink)
                    if let dictation {
                        HStack(spacing: 10) {
                            micButton(dictation)
                            Text(status(dictation))
                                .font(FATypography.sans(12, relativeTo: .caption))
                                .foregroundStyle(dictation.error == nil ? FAColor.inkSecondary : FAColor.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .modifier(FAGlassSurface(cornerRadius: 16))
                .transition(.opacity)
            }
        }
        .task {
            guard dictation == nil else { return }
            let meals = dependencies.meals
            let d = SpeechDictation(purpose: .answer) { audio, mime in try await meals.transcribe(audio: audio, mimeType: mime) }
            d.onFinal = { words in
                let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
                text = current.isEmpty ? words : current + " " + words
            }
            dictation = d
        }
    }

    private func status(_ d: SpeechDictation) -> String {
        if let error = d.error { return error }
        if d.listening { return String(localized: "note.voice.listening", defaultValue: "Listening… tap again when you're done") }
        if d.transcribing { return String(localized: "note.voice.transcribing", defaultValue: "Writing it down…") }
        return String(localized: "note.voice.hint", defaultValue: "Rather talk? Tap the mic and just say it.")
    }

    private func micButton(_ d: SpeechDictation) -> some View {
        Button { d.toggle() } label: {
            ZStack {
                Circle().fill(d.listening ? FAColor.danger : FAColor.forestSoft)
                if d.transcribing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: d.listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .opacity(d.listening && pulse ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(d.transcribing)
        .accessibilityLabel(d.listening
            ? String(localized: "note.voice.stop", defaultValue: "Stop and write it down")
            : String(localized: "note.voice.start", defaultValue: "Speak your note"))
        .onChange(of: d.listening) { _, on in
            if on { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } } else { withAnimation(.default) { pulse = false } }
        }
    }
}
