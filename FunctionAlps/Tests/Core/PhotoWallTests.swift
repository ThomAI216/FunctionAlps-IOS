import Foundation
import Testing
@testable import FunctionAlps

@Suite("Photo walls (Settings → Appearance)")
struct PhotoWallTests {
    /// The first-launch draw is stored, so the wall holds on every later launch until the member changes it.
    @Test func defaultIsAStoredPhoto() {
        let key = FAWalls.defaultKey
        #expect(FAPhotoWalls.photo(for: key) != nil || FAWalls.choices.contains(where: { $0.key == key }))
        #expect(UserDefaults.standard.string(forKey: FAWalls.storageKey) != nil)
    }

    @Test func gradientKeysAreNotPhotos() {
        for wall in FAWalls.choices {
            #expect(FAPhotoWalls.photo(for: wall.key) == nil)
        }
    }

    @Test func keysAreUniqueAndResolve() {
        let keys = FAPhotoWalls.all.map(\.key)
        #expect(Set(keys).count == keys.count)
        for photo in FAPhotoWalls.all {
            #expect(FAPhotoWalls.photo(for: photo.key) == photo)
            #expect(FAWalls.label(for: photo.key) == photo.label)
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
