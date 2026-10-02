@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// The live camera image. Letterboxed (`resizeAspect`), not cropped: what the member sees is exactly what
/// the pose engine sees, so "keep your hands in the frame" means the frame on screen. The preview layer
/// keeps its defaults: portrait (the app is portrait-only) and mirrored for the front camera, like any
/// selfie view. It displays frames; it stores none.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // The layer class is fixed above, so the cast cannot fail.
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
