import SwiftUI
import WebKit

/// The card's demonstration video (owner, 2026-10-08). Before a tap: the dark tile with its play button and title,
/// and nothing reaches YouTube. A YouTube link then plays right here, in YouTube's own player, with "Open in YouTube"
/// under it; any other link opens outside the app, as before. The paid host that comes later plays in AVKit from
/// the same tile (`ActionCardVideoSource`).
struct ActionCardVideoTile: View {
    @Environment(\.openURL) private var openURL
    let url: URL
    let title: String?
    let locale: String

    @State private var playing = false

    private var label: String {
        title ?? String(localized: "action.video.watch", defaultValue: "Watch the demonstration")
    }

    var body: some View {
        let source = ActionCardLogic.videoSource(url)
        if playing, case .youtube(let id, let start) = source,
           let embed = ActionCardLogic.youtubeEmbedURL(id: id, start: start, locale: locale),
           let origin = ActionCardLogic.youtubeClientOrigin(bundleID: Bundle.main.bundleIdentifier ?? "com.functionalps.patient") {
            VStack(alignment: .leading, spacing: 8) {
                videoFrame {
                    YouTubePlayerWebView(html: ActionCardLogic.youtubePlayerHTML(embed: embed, title: label), origin: origin) { openURL($0) }
                }
                Button { openURL(url) } label: {
                    Text(String(localized: "action.video.openYouTube", defaultValue: "Open in YouTube ↗"))
                        .font(FATypography.sans(13, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.forest)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                if case .youtube = source { playing = true } else { openURL(url) }
            } label: {
                videoFrame {
                    ZStack(alignment: .bottomLeading) {
                        FAColor.charcoal
                        Image(systemName: "play.fill").font(.system(size: 30)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Text(label)
                            .font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(.white.opacity(0.92))
                            .padding(12)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }

    /// 16:9 across the card, never under 200 points tall (YouTube's minimum player size); the tile and the player
    /// share it, so nothing jumps on play.
    private func videoFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity, minHeight: 200)
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// YouTube's embedded player in a web view — the one web view in the app, and only for this. A private, throwaway
/// data store (no cookies, no YouTube sign-in carried between videos or launches); the page identifies the app to
/// YouTube as its terms require (`origin` = `https://` + bundle id). A tap that would take the page elsewhere (the
/// title, the logo, "Watch on YouTube") opens outside the app.
private struct YouTubePlayerWebView: UIViewRepresentable {
    let html: String
    let origin: URL
    let openOutside: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(origin: origin, openOutside: openOutside) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.loadHTMLString(html, baseURL: origin)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let origin: URL
        private let openOutside: (URL) -> Void

        init(origin: URL, openOutside: @escaping (URL) -> Void) {
            self.origin = origin
            self.openOutside = openOutside
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // The player's own frame loads freely; the page itself only ever holds our HTML.
            if let frame = navigationAction.targetFrame, !frame.isMainFrame { return .allow }
            guard let url = navigationAction.request.url else { return .cancel }
            if url.host == origin.host || url.scheme == "about" { return .allow }
            leave(url)
            return .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { leave(url) }
            return nil
        }

        private func leave(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
            openOutside(url)
        }
    }
}
