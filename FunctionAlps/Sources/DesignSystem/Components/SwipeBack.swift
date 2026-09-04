import SwiftUI
import UIKit

/// Edge swipe to go back — the system interactive pop gesture. Every screen hides the system
/// navigation bar (each has its own `CenteredHeader`), and UIKit disables the gesture whenever the
/// bar is hidden. This re-enables it on the stack's `UINavigationController` with a delegate that
/// only lets it begin when there is somewhere to go back to (a swipe on a root screen would freeze
/// the stack). Installed on every root and every pushed destination, because the navigation
/// controller re-asserts its own delegate on some pushes.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.install() }

    final class Controller: UIViewController {
        private let popDelegate = PopGestureDelegate()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        func install() {
            guard let nav = navigationController ?? nearestNavigationController(), let gesture = nav.interactivePopGestureRecognizer else { return }
            popDelegate.navigationController = nav
            if gesture.delegate !== popDelegate { gesture.delegate = popDelegate }
            gesture.isEnabled = true
        }

        private func nearestNavigationController() -> UINavigationController? {
            var node: UIViewController? = parent
            while let current = node {
                if let nav = current as? UINavigationController { return nav }
                if let nav = current.navigationController { return nav }
                node = current.parent
            }
            return nil
        }
    }
}

@MainActor
final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
    }
}

extension View {
    /// Re-enables the edge swipe-back on this screen (see `SwipeBackEnabler`). Zero-size, no touches.
    func faSwipeBack() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
