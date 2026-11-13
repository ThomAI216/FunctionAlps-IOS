import SwiftUI
import UIKit

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// `UIActivityViewController`: the iPhone share sheet (Notes, Reminders, Messages, Mail, Files, AirDrop, Print).
/// Needs no permission. Items are text, URLs of files, or images. Shared by the data export and the grocery list.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
