import SwiftUI

/// What every macros / micros page needs: the member (targets, sex), the recent meals and today's
/// day row. One load per screen — the pages are pushed, never kept alive.
@MainActor
@Observable
final class NutritionScreenModel {
    private(set) var member: Member?
    private(set) var meals: [MealLog] = []
    private(set) var checkin: DailyCheckin?
    private(set) var loaded = false
    private(set) var errorMessage: String?
    private let calendar = Calendar.current

    func load(_ dependencies: AppDependencies) async {
        let members = dependencies.members
        let mealService = dependencies.meals
        let backend = dependencies.backend
        do {
            let member = try await members.currentMember()
            self.member = member
            let patientId = member.patientId
            let today = ISO8601.dayString(Date(), calendar: Calendar.current)
            async let recent = mealService.recentMeals(patientId: patientId)
            async let day: DailyCheckin? = { try? await backend.dailyCheckin(patientId: patientId, day: today) }()
            meals = try await recent
            checkin = await day
            errorMessage = nil
        } catch let error as AppError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = String(localized: "food.error.title", defaultValue: "Couldn't load your meals")
        }
        loaded = true
    }

    /// Re-read the profile row after the targets page saved.
    func replaceProfile(_ profile: MemberProfile?) {
        guard let member, let profile else { return }
        self.member = Member(userId: member.userId, patientId: member.patientId, email: member.email, displayName: member.displayName, profile: profile)
    }

    var profile: MemberProfile? { member?.profile }
    var sex: MemberProfile.Sex? { profile?.sex }

    /// Today's meals, oldest first.
    var todayMeals: [MealLog] {
        meals.filter { calendar.isDateInToday($0.loggedAt) }.sorted { $0.loggedAt < $1.loggedAt }
    }

    /// Per-nutrient sums over today's meals.
    var consumedToday: [String: Double] { MicroCoverage.consumed(from: todayMeals) }

    /// One value per day for a nutrient, the last `days` days, oldest first.
    func dailySeries(nutrientKey: String, days: Int) -> [(day: Date, value: Double)] {
        guard let field = MicroCoverage.nutrients.first(where: { $0.key == nutrientKey })?.field else { return [] }
        return (0..<days).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { return nil }
            let value = meals.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }.reduce(0.0) { $0 + ($1.micros[field] ?? 0) }
            return (day: calendar.startOfDay(for: day), value: value)
        }
    }
}

// MARK: - Shared pieces

/// The macros/micros header: back, centred display title, an optional trailing action.
struct NutritionHeader: View {
    let title: String
    var trailingSymbol: String? = nil
    var trailingTint: Color = FAColor.forestSoft
    var onTrailing: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium)).foregroundStyle(FAColor.ink)
                    .frame(width: 36, height: 36, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "action.back", defaultValue: "Go back"))
            Text(title).font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            if let trailingSymbol, let onTrailing {
                Button(action: onTrailing) {
                    Image(systemName: trailingSymbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(trailingTint)
                        .frame(width: 36, height: 36, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Coverage bands shared by the micro pages: ≥ 75 green · ≥ 50 amber · else red.
enum CoverageTone {
    static func color(_ pct: Int) -> Color {
        pct >= 75 ? Color(hex: 0x10B981) : pct >= 50 ? Color(hex: 0xF59E0B) : Color(hex: 0xEF4444)
    }
    static let red = Color(hex: 0xEF4444)
    static let amber = Color(hex: 0xF59E0B)
}

/// The Expo `CoverageRing`: a hairline track, a coloured arc from 12 o'clock, the percent inside.
struct CoverageRing: View {
    let pct: Int
    var size: CGFloat = 80
    var strokeWidth: CGFloat = 6
    let color: Color
    var subLabel: String? = nil
    @State private var fill: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(ProfilePalette.hairline, lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(Double(pct), 100) / 100 * fill))
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(pct)%").font(FATypography.sans(size >= 96 ? 22 : 16, .bold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                if let subLabel {
                    Text(subLabel).font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                }
            }
        }
        .frame(width: size, height: size)
        .mountFill($fill, duration: 1.2)
        .accessibilityLabel("\(pct)%")
    }
}

/// The Expo `MoleculeBadge`: a group-tinted chip with the element tile for minerals (symbol + atomic
/// number) and the nutrient's emoji for vitamins and fatty acids. The RDKit molecule renders of the
/// web app are SVG strings; the phone shows the emoji instead of embedding an SVG engine.
struct MoleculeBadge: View {
    let nutrient: NutrientCatalog.Nutrient
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(color.opacity(0.1))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(color.opacity(0.2), lineWidth: 1)
            if let element = NutrientCatalog.elements[nutrient.key] {
                Text("\(element.number)")
                    .font(FATypography.sans(max(7, size * 0.18), .semibold, relativeTo: .caption2)).foregroundStyle(color.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, size * 0.07).padding(.trailing, size * 0.12)
                Text(element.symbol).font(FATypography.display(size * 0.4, relativeTo: .body)).foregroundStyle(color).padding(.top, size * 0.08)
            } else {
                Text(nutrient.emoji).font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The faded card art behind the nutrient hero: the element symbol or the emoji, large and clipped.
struct MoleculeBackdrop: View {
    let nutrient: NutrientCatalog.Nutrient
    let color: Color

    var body: some View {
        Group {
            if let element = NutrientCatalog.elements[nutrient.key] {
                Text(element.symbol).font(FATypography.display(170, relativeTo: .largeTitle)).foregroundStyle(color)
            } else {
                Text(nutrient.emoji).font(.system(size: 150))
            }
        }
        .opacity(0.1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// Numbers on the micro pages: whole above 10, one decimal below (2.4 mcg, 157 mg).
enum NutrientFormat {
    static func amount(_ value: Double) -> String {
        if value >= 10 || value == 0 { return "\(Int(value.rounded()))" }
        return String(format: "%.1f", value)
    }
}

/// A small uppercase tracking label (the Expo 11 pt letter-spaced captions).
struct MicroLabel: View {
    let text: String
    var color: Color = ProfilePalette.muted
    var body: some View {
        Text(text.uppercased()).font(FATypography.sans(11, .bold, relativeTo: .caption2)).tracking(1.2).foregroundStyle(color)
    }
}
