import CoreGraphics
import Foundation
import Testing
@testable import FunctionAlps

/// The daily functional check-in's sleep dial and Bristol chart (owner, 2026-11-10).
@Suite("Sleep dial — a 24-hour ring, midnight at the top, clockwise")
struct SleepDialMathTests {
    private let center = CGPoint(x: 100, y: 100)

    @Test("A touch straight above the centre is midnight, right is 06:00, below is noon, left is 18:00")
    func cardinalTouches() {
        #expect(SleepDialMath.minutes(at: CGPoint(x: 100, y: 10), center: center) == 0)
        #expect(SleepDialMath.minutes(at: CGPoint(x: 190, y: 100), center: center) == 6 * 60)
        #expect(SleepDialMath.minutes(at: CGPoint(x: 100, y: 190), center: center) == 12 * 60)
        #expect(SleepDialMath.minutes(at: CGPoint(x: 10, y: 100), center: center) == 18 * 60)
    }

    @Test("A touch and the point drawn for its minutes agree, on 5-minute steps")
    func roundTrip() {
        for minutes in stride(from: 0, to: 1440, by: 35) {
            let snapped = SleepDialMath.snap(minutes)
            let p = SleepDialMath.point(minutes: snapped, center: center, radius: 80)
            #expect(SleepDialMath.minutes(at: p, center: center) == snapped)
        }
    }

    @Test("Snapping lands on 5 minutes and wraps 23:58 to midnight")
    func snapping() {
        #expect(SleepDialMath.snap(22 * 60 + 32) == 22 * 60 + 30)
        #expect(SleepDialMath.snap(22 * 60 + 33) == 22 * 60 + 35)
        #expect(SleepDialMath.snap(23 * 60 + 58) == 0)
        #expect(SleepDialMath.normalized(-15) == 1425)
    }

    @Test("A night across midnight is two arcs; a night inside one day is one")
    func arcs() {
        let across = SleepDialMath.arcSegments(bed: 22 * 60 + 30, wake: 6 * 60 + 30)
        #expect(across.count == 2)
        #expect(across[0].from == 1350.0 / 1440 && across[0].to == 1)
        #expect(across[1].from == 0 && across[1].to == 390.0 / 1440)
        let after = SleepDialMath.arcSegments(bed: 60, wake: 8 * 60)
        #expect(after.count == 1)
        #expect(SleepDialMath.arcSegments(bed: 300, wake: 300).isEmpty)
    }

    @Test("The centre reads the length as the member would say it")
    func durationLabel() {
        #expect(SleepDialMath.durationLabel(480) == "8 h")
        #expect(SleepDialMath.durationLabel(450) == "7 h 30")
        #expect(SleepDialMath.durationLabel(425) == "7 h 05")
    }

    @Test("A recorded night fills only a night nobody has answered")
    func unansweredNight() {
        #expect(CheckinEngine.sleepIsUnanswered(nil))
        #expect(CheckinEngine.sleepIsUnanswered(.empty))
        var told = DimAnswers.empty
        told.specials.bedTime = "23:00"
        #expect(!CheckinEngine.sleepIsUnanswered(told))
        var refreshedOnly = DimAnswers.empty
        refreshedOnly.sliders["refreshed"] = 70
        #expect(!CheckinEngine.sleepIsUnanswered(refreshedOnly))
    }

    @Test("Apple Health's asleep time travels with the night; a catalogue row's main-sleep duration too")
    func asleepMinutes() {
        let start = Date(timeIntervalSince1970: 1_789_247_400)
        let local = SleepNight(day: "2026-09-13", start: start, end: start.addingTimeInterval(7.5 * 3600),
                               asleepSeconds: 6.75 * 3600, inBedSeconds: 7.5 * 3600, remSeconds: 0, deepSeconds: 0,
                               lightSeconds: 0, awakeSeconds: 0, latencySeconds: 600, interruptions: 1)
        #expect(WearableNight(local: local).asleepMin == 405)
        let rows = [WearableNightRow(day: "2026-09-13", dataTypeId: WearableNightAssembler.duration, dataSourceId: 1_000_018, value: 25_200, timezoneOffset: 120)]
        #expect(WearableNightAssembler.night(from: rows)?.asleepMin == 420)
    }

    @Test("The daily check-in asks about last night first; the morning still does")
    @MainActor
    func dailyCheckinAsksSleep() {
        #expect(CheckinMomentViewModel.sections(for: .evening).first == .sleep)
        #expect(CheckinMomentViewModel.sections(for: .morning).first == .sleep)
        #expect(!CheckinMomentViewModel.sections(for: .midday).contains(.sleep))
    }
}

@Suite("Bristol chart — the tappable table")
struct BristolChartTests {
    @Test("Each row's middle answers its own type, 1 to 7")
    func rowMiddles() {
        for type in 1...7 {
            let r = BristolChart.rowRange(type)!
            #expect(BristolChart.type(atFraction: (r.lowerBound + r.upperBound) / 2) == type)
        }
    }

    @Test("Above the table and on the attribution below it, a tap answers nothing")
    func outsideTheTable() {
        #expect(BristolChart.type(atFraction: 0.001) == nil)
        #expect(BristolChart.type(atFraction: 0.95) == nil)
        #expect(BristolChart.rowRange(0) == nil)
        #expect(BristolChart.rowRange(8) == nil)
    }

    @Test("The rows run top to bottom without a gap")
    func contiguous() {
        for type in 1...6 {
            #expect(BristolChart.rowRange(type)!.upperBound == BristolChart.rowRange(type + 1)!.lowerBound)
        }
    }

    @Test("The chart ships with the app")
    func bundled() {
        #expect(FAMedia.image(BristolChart.imageName, ext: BristolChart.imageExt) != nil)
    }

    @Test("Every type has its pill words and the chart's own description")
    func labels() {
        for type in 1...7 {
            #expect(!GutSchema.bristolLabel(type).isEmpty)
            #expect(GutSchema.bristolDescription(type).hasPrefix("Type \(type)"))
        }
    }
}

@Suite("Glass — frost by wall")
struct GlassFrostTests {
    @Test("The light walls get the see-through glass; the photos keep the owner's 60 %")
    func frostByWall() {
        #expect(FAGlassSurface.frost(for: .gradient(.sageFog)) < FAGlassSurface.frost)
        if let photo = FAWalls.all.first(where: { if case .photo = $0 { true } else { false } }) {
            #expect(FAGlassSurface.frost(for: photo) == 0.60)
        }
    }
}
