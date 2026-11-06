import Foundation
import Testing
@testable import FunctionAlps

@Suite("Walls (Settings → Appearance)")
struct PhotoWallTests {
    /// The owner kept four of the eleven uploads (2026-09-30).
    @Test func theFourKeptPhotos() {
        #expect(FAPhotoWalls.all.map(\.file) == ["bg-blue-1", "bg-blue-3", "bg-sand-1", "bg-sand-4"])
    }

    /// Sage Fog is the owner's default (2026-11-06).
    @Test func defaultIsSageFog() {
        #expect(FAWalls.resolved(FAWalls.defaultKey) == .gradient(.sageFog))
    }

    /// The picker offers Sage Fog first, then the four photos.
    @Test func pickerOrder() {
        #expect(FAWalls.all.map(\.key) == ["gradient.sage-fog", "photo.bg-blue-1", "photo.bg-blue-3", "photo.bg-sand-1", "photo.bg-sand-4"])
    }

    /// A retired wall (an old gradient, or a photo the owner dropped) falls back to the default.
    @Test func retiredKeysResolveToTheDefault() {
        for key in ["dd9", "dd7", "photo.bg-sand-5", "gradient.sage", ""] {
            #expect(FAWalls.wall(for: key) == nil)
            #expect(FAWalls.resolved(key) == .gradient(.sageFog))
        }
    }

    @Test func keysAreUniqueAndResolve() {
        let keys = FAWalls.all.map(\.key)
        #expect(Set(keys).count == keys.count)
        for wall in FAWalls.all {
            #expect(FAWalls.resolved(wall.key) == wall)
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
