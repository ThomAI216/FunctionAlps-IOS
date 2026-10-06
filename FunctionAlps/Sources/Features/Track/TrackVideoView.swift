import AVKit
import SwiftUI

/// The day's ~1-minute video, played in the card (AVKit's `VideoPlayer`, no package). Nothing loads until the
/// member taps play — a video per day must not cost data on every Home open. The first tap reports `onPlay` (the
/// day's `video` activity). No URL yet (Thomas records them in French and English) → a calm "coming soon" pane.
struct TrackVideoView: View {
    let url: URL?
    let onPlay: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let url {
                ZStack {
                    if let player {
                        VideoPlayer(player: player)
                    } else {
                        Button { start(url) } label: { poster }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "track.video.play", defaultValue: "Play today's video"))
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onDisappear { player?.pause() }
            } else {
                comingSoon
            }
        }
    }

    private func start(_ url: URL) {
        // Sound even with the silent switch on: the member asked for this video by tapping play.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let p = AVPlayer(url: url)
        player = p
        p.play()
        onPlay()
    }

    private var poster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FAColor.forestDark)
            VStack(spacing: 8) {
                Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text(String(localized: "track.video.watch", defaultValue: "Today's video · about 1 minute"))
                    .font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(.white.opacity(0.92))
            }
        }
    }

    private var comingSoon: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle").font(.system(size: 18, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
                .frame(width: 40, height: 40)
                .background(FAColor.forestSoft.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(String(localized: "track.video.soon", defaultValue: "Today's video is coming soon."))
                .font(FATypography.callout).foregroundStyle(FAColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .modifier(FAGlassSurface(cornerRadius: 14, inset: true))
        .accessibilityElement(children: .combine)
    }
}
