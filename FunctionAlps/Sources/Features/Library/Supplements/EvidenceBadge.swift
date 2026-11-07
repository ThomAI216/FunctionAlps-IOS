import SwiftUI

/// The evidence level as a WORD and DOTS (four of them; not supported draws a dash) — never colour alone (rule 10).
struct EvidenceBadge: View {
    let level: EvidenceLevel

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                if let filled = level.dots {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(i < filled ? level.tint : Color.black.opacity(0.12)).frame(width: 6, height: 6)
                    }
                } else {
                    Text("—").font(FATypography.sans(10, .bold, relativeTo: .caption2)).foregroundStyle(level.tint)
                }
            }
            .accessibilityHidden(true)
            Text(level.label).font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).foregroundStyle(level.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.label)
    }
}

/// The evidence card at the top of a use: the word, a four-segment bar, the scale under it, and one line on what
/// the studies were (from the payload), with its sources.
struct EvidenceCard: View {
    let evidence: SupplementEvidence
    let sources: [SourceRef]
    let onSource: (SourceKey) -> Void

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 8) {
                Text(evidence.level.label).font(FATypography.display(18, relativeTo: .title3)).foregroundStyle(evidence.level.tint)
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(i < (evidence.level.dots ?? 0) ? evidence.level.tint : evidence.level.emptyTint).frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
                HStack {
                    ForEach([EvidenceLevel.weak, .limited, .moderate, .strong], id: \.self) { step in
                        Text(step.scaleWord).font(FATypography.sans(8.5, relativeTo: .caption2)).foregroundStyle(FAColor.stone)
                        if step != .strong { Spacer(minLength: 0) }
                    }
                }
                .accessibilityHidden(true)
                if let line = evidence.line, !line.isEmpty {
                    SupplementItemRow(item: SupplementItem(text: line, sources: evidence.basis), style: .plain, sources: sources, onSource: onSource)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(evidence.level.label)
    }
}

extension EvidenceLevel {
    /// A tint beside the word, never instead of it.
    var tint: Color {
        switch self {
        case .strong, .moderate: FAColor.forest
        case .limited, .weak: Color(hex: 0x9A6416)
        case .notSupported: Color(hex: 0x9F2D3A)
        }
    }

    var emptyTint: Color {
        self == .notSupported ? Color(hex: 0x9F2D3A, opacity: 0.14) : Color.black.opacity(0.08)
    }

    /// The single word on the scale under the bar.
    var scaleWord: String {
        switch self {
        case .strong: String(localized: "supplement.scale.strong", defaultValue: "Strong")
        case .moderate: String(localized: "supplement.scale.moderate", defaultValue: "Moderate")
        case .limited: String(localized: "supplement.scale.limited", defaultValue: "Limited")
        case .weak: String(localized: "supplement.scale.weak", defaultValue: "Weak")
        case .notSupported: String(localized: "supplement.evidence.notSupported", defaultValue: "Not supported")
        }
    }
}
