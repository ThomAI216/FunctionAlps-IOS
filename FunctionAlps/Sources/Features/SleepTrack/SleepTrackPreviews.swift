import SwiftUI

/// Sample data + Xcode previews for the Sleep track. Nothing here ships a value
/// to a member: every figure is invented, and it is invented to exercise the hard
/// cases rather than a tidy night.
///
/// Open any of the `#Preview`s below in the canvas to review the screens.
enum SleepTrackSample {
    /// A fortnight in progress: six nights in, two mornings missed, one of them
    /// still inside its 48-hour window.
    static var track: SleepTrack {
        var nights: [MorningLog] = (1...6).map { i in
            var log = MorningLog(day: String(format: "2026-09-%02d", i))
            // Night 4 was missed; night 6 is this morning, still open.
            if i != 4 && i != 6 {
                log.inBed = "22:40"
                log.trySleep = "23:15"
                log.latencyMin = 37
                log.awakenings = 2
                log.wasoMin = i == 3 ? 90 : 22
                log.finalWake = "06:20"
                log.outOfBed = "06:55"
                log.restoration = i == 3 ? 2 : 5
                log.sleepiness = i == 3 ? 8 : 4
                log.overall = i == 3 ? 3 : 6
                log.unusual = i == 3 ? ["alcohol"] : []
                log.completedAt = .now
                log.recallDelayMin = 25
            }
            return log
        }
        // The open morning carries the member's usual times as a starting point
        // for the pickers only — nothing is stored until they save.
        nights[5].inBed = nil
        var t = SleepTrack(intent: .baseline, length: .standard, startedOn: "2026-09-01", nights: nights)
        t.freeDays = ["2026-09-06", "2026-09-07", "2026-09-13", "2026-09-14"]
        return t
    }

    /// What Apple Health assembled for the same night. Note it has real `start`
    /// and `end` timestamps — HealthKit gives us the timing that Thryve's daily
    /// scalars never did. It still does not know when the member got into bed.
    static var night: SleepNight {
        let end = Calendar.current.date(bySettingHour: 6, minute: 31, second: 0, of: Date()) ?? Date()
        let start = end.addingTimeInterval(-7 * 3600 - 20 * 60)
        return SleepNight(
            day: "2026-09-06",
            start: start,
            end: end,
            asleepSeconds: 6 * 3600 + 44 * 60,
            inBedSeconds: 7 * 3600 + 20 * 60,
            remSeconds: 5400,
            deepSeconds: 3300,
            lightSeconds: 15_540,
            awakeSeconds: 2160,
            latencySeconds: 0,   // a live device default — never written into M03
            interruptions: 3
        )
    }

    static var openMorning: MorningLog { track.nights[5] }
}

#Preview("Morning log") {
    MorningLogView(
        log: SleepTrackSample.openMorning,
        night: SleepTrackSample.night,
        nightNumber: 6,
        totalNights: 14
    )
    .background(FAColor.background)
}

#Preview("Start a track") {
    SleepTrackStartView()
        .background(FAColor.background)
}

#Preview("Where you are") {
    SleepTrackProgressView(track: SleepTrackSample.track, watchNights: 6)
        .background(FAColor.background)
}

#Preview("Home cards") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            label("No track running")
            SleepTrackInviteCard()
            label("Running · this morning still open")
            SleepTrackMorningCard(track: SleepTrackSample.track, watchSynced: true)
            label("Logged")
            SleepTrackLoggedCard(track: SleepTrackSample.track)
            label("A morning was missed")
            SleepTrackBackfillCard(dayLabel: "Tuesday")
        }
        .padding(FASpacing.md)
    }
    .background(FAColor.background)
}

@ViewBuilder
private func label(_ text: String) -> some View {
    Text(text.uppercased())
        .font(FATypography.label)
        .tracking(0.8)
        .foregroundStyle(FAColor.inkMuted)
}
