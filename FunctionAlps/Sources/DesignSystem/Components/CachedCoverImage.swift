import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// Remote cover art, cached on disk for good. Covers are immutable per URL (STUDIO writes a new,
/// timestamped file on every swap), so an entry never needs revalidating: the file cache is keyed by
/// the URL and never expires, and decoded images are kept in memory at display size. No third-party
/// package (CLAUDE.md rule 8): URLSession + ImageIO + a folder in Caches.
actor RemoteImageStore {
    static let shared = RemoteImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private var downloads: [URL: Task<Data?, Never>] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("cover-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 60
    }

    /// The image at `url`, downsampled so its longer side is at most `maxPixel` pixels; nil on any failure.
    func image(for url: URL, maxPixel: Int) async -> UIImage? {
        let memoryKey = "\(maxPixel)|\(url.absoluteString)" as NSString
        if let hit = memory.object(forKey: memoryKey) { return hit }
        guard let data = await data(for: url), let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
        memory.setObject(image, forKey: memoryKey)
        return image
    }

    private func data(for url: URL) async -> Data? {
        let file = directory.appendingPathComponent(Self.fileName(for: url))
        if let cached = try? Data(contentsOf: file) { return cached }
        if let running = downloads[url] { return await running.value }
        let task = Task<Data?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
            return data
        }
        downloads[url] = task
        let data = await task.value
        downloads[url] = nil
        if let data { try? data.write(to: file, options: .atomic) }
        return data
    }

    private static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes straight to display size (a 1600×900 master never sits in memory at full size).
    private static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A cover filling whatever frame it is given (cover fit, centred), fading in over what sits behind it —
/// callers put the pillar gradient there, so a slow, failed or missing image never leaves an empty frame.
/// Decorative: hidden from VoiceOver (the title sits right next to it).
struct CachedCoverImage: View {
    let url: URL?
    /// Longest side after decoding, in pixels; 16:9 masters are 1600 wide.
    var maxPixel: Int = 1100
    @State private var image: UIImage?
    @State private var shownURL: URL?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; shownURL = nil; return }
                if shownURL != url { image = nil }
                guard let loaded = await RemoteImageStore.shared.image(for: url, maxPixel: maxPixel) else { return }
                shownURL = url
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}
