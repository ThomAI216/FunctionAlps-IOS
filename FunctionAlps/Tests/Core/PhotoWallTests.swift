import Foundation
import Testing
@testable import FunctionAlps

@Suite("Photo walls (Settings → Appearance)")
struct PhotoWallTests {
    @Test func randomIsTheDefaultAndResolvesToAPhoto() {
        #expect(FAWalls.defaultKey == FAPhotoWalls.randomKey)
        let pick = FAPhotoWalls.photo(for: FAPhotoWalls.randomKey)
        #expect(pick != nil)
        #expect(pick == FAPhotoWalls.photo(for: FAPhotoWalls.randomKey)) // one pick for the whole launch
    }

    @Test func gradientKeysAreNotPhotos() {
        for wall in FAWalls.choices {
            #expect(FAPhotoWalls.photo(for: wall.key) == nil)
        }
    }

    @Test func keysAreUniqueAndResolve() {
        let keys = FAPhotoWalls.all.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(!keys.contains(FAPhotoWalls.randomKey))
        for photo in FAPhotoWalls.all {
            #expect(FAPhotoWalls.photo(for: photo.key) == photo)
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
