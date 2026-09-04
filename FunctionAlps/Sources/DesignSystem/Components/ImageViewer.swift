import SwiftUI
import UIKit

/// Full-screen image viewer: pinch to zoom (1×–5×), pan, double-tap to zoom in/out, swipe down or
/// tap the close button to leave. UIScrollView drives the zoom because it is the one zoom behaviour
/// members already know from Photos; SwiftUI gestures alone drift and overshoot.
struct ImageViewer: View {
    let image: UIImage
    var caption: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var zoomed = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(1 - min(0.6, Double(abs(dragOffset)) / 600)).ignoresSafeArea()
            ZoomableImage(image: image, zoomed: $zoomed)
                .ignoresSafeArea()
                .offset(y: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            // Only a downward drag while NOT zoomed dismisses; zoomed panning belongs to the scroll view.
                            if !zoomed, value.translation.height > 0 { dragOffset = value.translation.height }
                        }
                        .onEnded { value in
                            if !zoomed, value.translation.height > 120 { dismiss() } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = 0 }
                            }
                        }
                )
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "action.close", defaultValue: "Close"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if let caption, !caption.isEmpty, !zoomed {
                Text(caption)
                    .font(FATypography.sans(12, relativeTo: .caption))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: zoomed)
        .statusBarHidden(true)
    }
}

/// UIScrollView + UIImageView: aspect-fit at 1×, content kept centred at every scale.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var zoomed: Bool

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true
        // No bounce at 1×: with nothing to scroll the pan recogniser stays idle, so the swipe-down
        // reaches the SwiftUI drag that dismisses the viewer.
        scroll.bounces = false
        scroll.alwaysBounceVertical = false
        scroll.alwaysBounceHorizontal = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        if scroll.bounds.size != context.coordinator.lastBounds {
            context.coordinator.lastBounds = scroll.bounds.size
            imageView.frame = CGRect(origin: .zero, size: scroll.bounds.size)
            scroll.contentSize = scroll.bounds.size
            scroll.zoomScale = 1
            context.coordinator.centre(scroll)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(zoomed: $zoomed) }

    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var lastBounds: CGSize = .zero
        private let zoomed: Binding<Bool>

        init(zoomed: Binding<Bool>) { self.zoomed = zoomed }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centre(scrollView)
            let isZoomed = scrollView.zoomScale > 1.01
            if zoomed.wrappedValue != isZoomed { zoomed.wrappedValue = isZoomed }
        }

        /// Keeps a small image centred instead of pinned top-left as the content grows.
        func centre(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let bounds = scrollView.bounds.size
            let frame = imageView.frame
            let x = max(0, (bounds.width - frame.width) / 2)
            let y = max(0, (bounds.height - frame.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView, let imageView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// Loads a remote image once into a `UIImage` (AsyncImage only hands back a SwiftUI `Image`,
/// and the viewer needs the bitmap). In-memory cache keyed by URL for the session.
@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()
    private var images: [URL: UIImage] = [:]
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL) async -> UIImage? {
        if let hit = images[url] { return hit }
        if let task = inflight[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let result = try? await URLSession.shared.data(from: url) else { return nil }
            return UIImage(data: result.0)
        }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        if let result { images[url] = result }
        return result
    }
}
