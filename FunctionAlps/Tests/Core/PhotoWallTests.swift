import Foundation
import Testing
@testable import FunctionAlps

@Suite("Photo walls (Settings → Appearance)")
struct PhotoWallTests {
    /// The owner kept four of the eleven uploads (2026-09-30).
    @Test func theFourKeptPhotos() {
        #expect(FAPhotoWalls.all.map(\.file) == ["bg-blue-1", "bg-blue-3", "bg-sand-1", "bg-sand-4"])
    }

    /// The first-launch draw is stored, so the wall holds on every later launch until the member changes it.
    @Test func defaultIsAStoredPhoto() {
        let key = FAWalls.defaultKey
        #expect(FAPhotoWalls.photo(for: key) != nil)
        #expect(UserDefaults.standard.string(forKey: FAWalls.storageKey) != nil)
    }

    /// A retired wall (a gradient, or a photo the owner dropped) falls back to the default photo.
    @Test func retiredKeysResolveToTheDefault() {
        let fallback = FAWalls.resolved(FAWalls.defaultKey)
        for key in ["dd9", "dd7", "photo.bg-sand-5", ""] {
            #expect(FAPhotoWalls.photo(for: key) == nil)
            #expect(FAWalls.resolved(key) == fallback)
        }
    }

    @Test func keysAreUniqueAndResolve() {
        let keys = FAPhotoWalls.all.map(\.key)
        #expect(Set(keys).count == keys.count)
        for photo in FAPhotoWalls.all {
            #expect(FAWalls.resolved(photo.key) == photo)
        }
    }

    /// A missing file would silently show only the tint, so every photo must ship in the app bundle.
    @Test func everyPhotoShipsInTheBundle() {
        for photo in FAPhotoWalls.all {
            #expect(PhotoWallImages.full(photo) != nil, "missing \(photo.file).jpg")
            #expect(PhotoWallImages.thumbnail(photo) != nil, "no thumbnail for \(photo.file).jpg")
        }
    }
}
