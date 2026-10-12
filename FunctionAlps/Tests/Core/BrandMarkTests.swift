import Testing
import UIKit
@testable import FunctionAlps

// The check-in slider's thumb and the fallback brand tile draw the FunctionAlps mark from the asset catalog. It
// must ship, and as a TEMPLATE image: only then does it take the slider state's colour instead of its own pixels.
@Suite("Brand mark — the tintable FunctionAlps logo")
struct BrandMarkTests {
    @Test func theMarkShipsAsATemplateImage() throws {
        let mark = try #require(UIImage(named: "FAMark", in: Bundle(for: HabitsService.self), compatibleWith: nil))
        #expect(mark.renderingMode == .alwaysTemplate)
        #expect(mark.size.width == mark.size.height)   // square, so it sits centred in the round thumb
    }
}
