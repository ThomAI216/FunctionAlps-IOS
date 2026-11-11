#if DEBUG
import Foundation

/// The showcase's signal explanations: SAMPLE data for the screenshots, never production copy. `ShowcaseSignalContent.json`
/// is generated from the same seed as migration `20261111090000_signal_explanations.sql` (14 rows: 7 signals × en/fr), so the
/// shots show what a member will read once the practice's content is applied. Debug builds only: this file, and the JSON's
/// only reader, compile out of Release.
enum ShowcaseSignals {
    static func rows(locale: String) -> [SignalExplanation] {
        guard let url = Bundle.main.url(forResource: "ShowcaseSignalContent", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSON.decode([SignalExplanation].self, from: data) else { return [] }
        return rows.filter { $0.locale == locale }
    }
}
#endif
