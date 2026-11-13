import AVKit
import SwiftUI
import UIKit
import WebKit
import os

/// The app is portrait; a video on screen may also turn. `AppDelegate` answers the system's question from here.
enum PlayerOrientation {
    private static let landscapeAllowed = OSAllocatedUnfairLock(initialState: false)

    static var mask: UIInterfaceOrientationMask { landscapeAllowed.withLock { $0 } ? .allButUpsideDown : .portrait }

    @MainActor
    static func allowLandscape(_ allowed: Bool) {
        landscapeAllowed.withLock { $0 = allowed }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        // Leaving the video puts the app back upright, even if the phone is still on its side.
        if !allowed { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in } }
    }
}

/// A habit's video, played in the app (Thomas, 2026-11-10): our own videos with the app's AVPlayer (as the day's
/// video), YouTube's with its own embedded player. The player is full width under the header; when the phone turns
/// it fills the screen.
struct LibraryVideoView: View {
    let video: LibraryVideo
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var player: AVPlayer?

    /// iPhone on its side: the height is "compact".
    private var landscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            let height = landscape ? geo.size.height : geo.size.width * 9 / 16
            VStack(spacing: 0) {
                surface
                    .frame(width: geo.size.width, height: height)
                    .background(Color.black)
                if !landscape {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(LibraryVideoCopy.source(video).uppercased())
                                .font(FATypography.sans(10, .bold, relativeTo: .caption)).tracking(1.2).foregroundStyle(FALibraryColor.gold)
                            Text(video.title).font(FATypography.display(24, relativeTo: .title)).foregroundStyle(FAColor.ink)
                                .accessibilityAddTraits(.isHeader)
                            LibraryPracticeSection(source: .video(url: video.url))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, FASpacing.navBarClearance)
                    }
                }
            }
        }
        .background(landscape ? Color.black : Color.clear)
        .ignoresSafeArea(edges: landscape ? .all : [])
        .faWall()
        .statusBarHidden(landscape)
        .persistentSystemOverlays(landscape ? .hidden : .automatic)
        .toolbar(landscape ? .hidden : .visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(String(localized: "library.watch.title", defaultValue: "Watch"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            PlayerOrientation.allowLandscape(true)
            startOwnVideo()
        }
        .onDisappear {
            PlayerOrientation.allowLandscape(false)
            player?.pause()
        }
    }

    @ViewBuilder
    private var surface: some View {
        if let id = video.youtubeID {
            YouTubePlayerView(videoID: id)
                .accessibilityLabel(video.title)
        } else if let player {
            VideoPlayer(player: player)
        } else {
            Color.black
        }
    }

    /// Sound even with the silent switch on: the member asked for this video by tapping it.
    private func startOwnVideo() {
        guard video.youtubeID == nil, player == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let p = AVPlayer(url: video.url)
        player = p
        p.play()
    }
}

/// YouTube's own player, for one video: its embed page in a minimal `WKWebView` (no package; the only way to play a
/// YouTube video inside the app within YouTube's terms). Nothing else loads in it: any link or new window the page
/// asks for is refused, and it keeps no cookies or storage after the screen closes.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        web.load(Self.request(videoID: videoID))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    /// The page the iframe is embedded from: a real https origin, which YouTube's embed player asks to identify.
    static let origin = URL(string: "https://www.functionalps.ch")

    /// The embed page itself, loaded directly with our origin as the referrer: YouTube's embed player refuses to play
    /// ("Video unavailable") when it cannot identify the embedding site, which an iframe inside a local HTML string
    /// does not reliably give it in WKWebView.
    static func request(videoID: String) -> URLRequest {
        var c = URLComponents(string: "https://www.youtube-nocookie.com/embed/\(videoID)")!
        c.queryItems = [URLQueryItem(name: "playsinline", value: "1"), URLQueryItem(name: "rel", value: "0"),
                        URLQueryItem(name: "autoplay", value: "1"), URLQueryItem(name: "origin", value: "https://www.functionalps.ch"),
                        URLQueryItem(name: "widget_referrer", value: "https://www.functionalps.ch")]
        var r = URLRequest(url: c.url!)
        r.setValue("https://www.functionalps.ch/", forHTTPHeaderField: "Referer")
        return r
    }

    static func html(videoID: String) -> String {
        let src = "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1&autoplay=1"
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="\(src)" title="YouTube video player" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// The embed page loads once; a tapped link or a new window (the "Watch on YouTube" link) never leaves the app.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated { return .cancel }
            return .allow
        }
    }
}
