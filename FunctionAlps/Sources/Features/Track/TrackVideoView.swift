import AVKit
import SwiftUI

/// The day's short motion film (9:16 vertical, 1080 × 1920, 20–45 s; owner 2026-10-12: "make them 9:16, for phone
/// view; when people click it opens full window 9:16"). On the card it is a compact 16:9 tile — a play button and
/// "Today's video" over the forest gradient — so Home stays short; a tap opens the film full screen on black, aspect
/// fit, playing at once. Nothing loads until that tap: a film a day must not cost data on every Home open, so the
/// tile shows the first frame only when the file is already on the phone (`TrackLogic.canGrabPoster`). The film's
/// first start reports `onPlay` (the day's `video` activity, recorded once by `TrackService`). No URL yet → a calm
/// "coming soon" pane.
struct TrackVideoView: View {
    let url: URL?
    let onPlay: () -> Void
    @State private var playing = false
    @State private var poster: UIImage?

    var body: some View {
        if let url {
            Button { playing = true } label: { tile }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "track.video.play", defaultValue: "Play today's video"))
                .accessibilityAddTraits(.isButton)
                .task(id: url) {
                    guard TrackLogic.canGrabPoster(url) else { return }
                    poster = await Self.firstFrame(url)
                }
                .fullScreenCover(isPresented: $playing) {
                    TrackVideoPlayerScreen(url: url, onPlay: onPlay)
                }
        } else {
            comingSoon
        }
    }

    private var tile: some View {
        ZStack {
            LinearGradient(colors: [FAColor.forestDark, FAColor.forest], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let poster {
                Image(uiImage: poster).resizable().scaledToFill()
                Color.black.opacity(0.25)
            }
            VStack(spacing: 8) {
                Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white)
                Text(String(localized: "track.video.watch", defaultValue: "Today's video"))
                    .font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
            }
            .padding(12)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    /// The first frame of a file already on the phone, cropped by the tile. Never called for a remote URL.
    nonisolated private static func firstFrame(_ url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        guard let frame = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: frame.image)
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

/// The film, full screen on black: 9:16 aspect fit (nothing cropped on any iPhone), playing at once, no loop, the
/// mute switch respected (the session is left as AVKit has it). Close top-leading inside the safe area; a swipe down
/// closes too.
private struct TrackVideoPlayerScreen: View {
    let url: URL
    let onPlay: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: drag)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "action.close", defaultValue: "Close"))
            .padding(.leading, 16).padding(.top, 8)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in drag = max(0, value.translation.height) }
                .onEnded { value in
                    if value.translation.height > 120 { dismiss() } else { withAnimation(.easeOut(duration: 0.2)) { drag = 0 } }
                }
        )
        .onAppear {
            guard player == nil else { return }
            let p = AVPlayer(url: url)
            player = p
            p.play()
            onPlay()
        }
        .onDisappear { player?.pause() }
    }
}
