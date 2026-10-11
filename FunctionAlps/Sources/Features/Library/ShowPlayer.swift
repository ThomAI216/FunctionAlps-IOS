import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The episode's replay: the video when there is one, else the audio, in one AVPlayer the screen drives (play /
/// pause, the progress line, chapter jumps). Nothing loads until the first play.
@MainActor
@Observable
final class ShowPlayer {
    private(set) var isPlaying = false
    private(set) var started = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isVideo = false
    private(set) var url: URL?

    let player = AVPlayer()
    @ObservationIgnored private var observer: Any?

    var hasMedia: Bool { url != nil }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }

    /// Video wins over audio (the replay with chapters is the same recording).
    func configure(video: URL?, audio: URL?, durationSeconds: Int?) {
        guard url == nil else { return }
        url = video ?? audio
        isVideo = video != nil
        duration = Double(durationSeconds ?? 0)
    }

    func toggle() {
        guard url != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            play()
        }
    }

    /// Jump to a chapter and play from there.
    func seek(to seconds: Int) {
        guard url != nil else { return }
        load()
        player.seek(to: CMTime(seconds: Double(seconds), preferredTimescale: 600))
        position = Double(seconds)
        play()
    }

    func stop() {
        player.pause()
        isPlaying = false
        if let observer {
            player.removeTimeObserver(observer)
            self.observer = nil
        }
    }

    private func play() {
        load()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: isVideo ? .moviePlayback : .spokenAudio)
        try? session.setActive(true)
        player.play()
        isPlaying = true
        started = true
    }

    private func load() {
        guard let url else { return }
        if player.currentItem == nil {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        if observer == nil {
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
                let seconds = time.seconds
                MainActor.assumeIsolated { self?.tick(seconds) }
            }
        }
    }

    private func tick(_ seconds: Double) {
        if seconds.isFinite { position = seconds }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        isPlaying = player.rate > 0
    }
}

/// The video surface (an AVPlayerLayer filling the 16:9 frame).
struct ShowVideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        // swiftlint:disable:next force_cast
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// The player card of the episode page (mockup AppEpisode): 16:9, the episode's cover dimmed on near-black, the gold
/// play button in the middle, the progress line along the bottom. Without a replay: the cover and a quiet note.
struct ShowPlayerView: View {
    let player: ShowPlayer
    let topic: String
    let cover: URL?

    private static let progressGold = Color(hex: 0xE6C27A)

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack {
                    Color(hex: 0x1A1A16)
                    let (from, to) = LibraryLogic.pillarGradient(topic)
                    LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.75)
                    CachedCoverImage(url: cover).opacity(0.75)
                    if player.isVideo && player.started {
                        ShowVideoSurface(player: player.player)
                    }
                    if player.hasMedia {
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(FALibraryColor.gold, in: Circle())
                                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        .opacity(player.isPlaying && player.isVideo ? 0.55 : 1)
                        .accessibilityLabel(player.isPlaying ? String(localized: "show.pause", defaultValue: "Pause") : String(localized: "show.play", defaultValue: "Play the replay"))
                    } else {
                        Text(String(localized: "show.noReplay", defaultValue: "The replay is not online yet."))
                            .font(FATypography.sans(12, .semibold, relativeTo: .footnote))
                            .foregroundStyle(FAColor.charcoal)
                            .faFrost(cornerRadius: 12, horizontal: 12, vertical: 7)
                    }
                }
                .overlay(alignment: .bottom) {
                    if player.hasMedia {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.35))
                                Capsule().fill(Self.progressGold).frame(width: geo.size.width * player.progress)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .accessibilityHidden(true)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
