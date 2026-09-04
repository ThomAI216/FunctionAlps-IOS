import SwiftUI

// MARK: - Hub (the Expo `(screens)/micronutrients.tsx`)

/// Today's coverage across the 21 tracked nutrients, the gaps, then one card per group.
struct MicronutrientsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model = NutritionScreenModel()
    @State private var showAllGaps = false

    var body: some View {
        VStack(spacing: 0) {
            NutritionHeader(title: String(localized: "micros.title", defaultValue: "Micronutrients"))
            ScrollView(showsIndicators: false) {
                if !model.loaded {
                    FALoadingState().padding(.top, 60)
                } else {
                    let consumed = model.consumedToday
                    let overall = MicroCoverage.overall(meals: model.todayMeals, sex: model.sex) ?? 0
                    let gaps = NutritionMath.gaps(threshold: 0.7, sex: model.sex, limit: 99, consumed: consumed).map(\.nutrient)
                    VStack(alignment: .leading, spacing: 0) {
                        heroCard(overall: overall, gaps: gaps).padding(.bottom, 20)
                        Text(String(localized: "micros.byCategory", defaultValue: "By category").uppercased())
                            .font(FATypography.sans(11, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(ProfilePalette.muted).padding(.bottom, 12).padding(.leading, 2)
                        ForEach(NutrientCatalog.groups) { group in
                            GroupCard(group: group, sex: model.sex, consumed: consumed) { router.push(.microGroup(group.key.rawValue)) }
                                .padding(.bottom, 12)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, FASpacing.navBarClearance)
                }
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load(dependencies) }
    }

    private func heroCard(overall: Int, gaps: [NutrientCatalog.Nutrient]) -> some View {
        let color = CoverageTone.color(overall)
        let label = overall >= 75 ? String(localized: "micros.band.onTrack", defaultValue: "On Track") : overall >= 50 ? String(localized: "micros.band.attention", defaultValue: "Needs Attention") : String(localized: "micros.band.critical", defaultValue: "Critical Gaps")
        return FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 20) {
                    CoverageRing(pct: overall, size: 96, color: color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label).font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
                        Text(String(localized: "micros.hero.body", defaultValue: "Today's micronutrient coverage across all tracked nutrients")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                    }
                }
                if !gaps.isEmpty {
                    Button { withAnimation(.spring(duration: 0.3)) { showAllGaps.toggle() } } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            FlowLayout(spacing: 6) {
                                ForEach(showAllGaps ? gaps : Array(gaps.prefix(3))) { gap in
                                    chip(gap.name, color: CoverageTone.red)
                                }
                                if !showAllGaps, gaps.count > 3 {
                                    HStack(spacing: 3) {
                                        Text(String(localized: "micros.more", defaultValue: "+\(gaps.count - 3) more")).font(FATypography.sans(11, .semibold, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(ProfilePalette.muted)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 3).background(ProfilePalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            if showAllGaps {
                                Text(String(localized: "micros.gaps.note", defaultValue: "◆ These gaps are summarized in your weekly report, so you and your practitioner can track them over time."))
                                    .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).lineSpacing(4)
                            }
                        }
                        .padding(.top, 12).overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }.padding(.top, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text).font(FATypography.sans(11, .semibold, relativeTo: .caption2)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// One group: ring, name, "N nutrients tracked", the gap badge, the first four nutrient dots.
private struct GroupCard: View {
    let group: NutrientCatalog.Group
    let sex: MemberProfile.Sex?
    let consumed: [String: Double]
    let onTap: () -> Void

    var body: some View {
        let nutrients = NutrientCatalog.nutrients(in: group.key)
        let coverage = NutritionMath.groupCoverage(group.key, sex: sex, consumed: consumed)
        let gaps = nutrients.filter { NutritionMath.coveragePercent(consumed: consumed[$0.key] ?? 0, target: $0.target(sex: sex)) < 75 }
        Button(action: onTap) {
            FACard {
                HStack(spacing: 12) {
                    CoverageRing(pct: coverage, size: 68, color: group.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                        Text(String(localized: "micros.tracked", defaultValue: "\(nutrients.count) nutrients tracked")).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted)
                        if !gaps.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle").font(.system(size: 10, weight: .bold))
                                Text(gaps.count > 1 ? String(localized: "micros.gaps.n", defaultValue: "\(gaps.count) gaps") : String(localized: "micros.gaps.one", defaultValue: "1 gap"))
                                    .font(FATypography.sans(11, .semibold, relativeTo: .caption2))
                            }
                            .foregroundStyle(CoverageTone.red)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(CoverageTone.red.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 5) {
                        ForEach(nutrients.prefix(4)) { n in
                            let pct = NutritionMath.coveragePercent(consumed: consumed[n.key] ?? 0, target: n.target(sex: sex))
                            HStack(spacing: 5) {
                                Text(n.name).font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted).lineLimit(1)
                                Circle().fill(CoverageTone.color(pct)).frame(width: 7, height: 7)
                            }
                        }
                        if nutrients.count > 4 {
                            Text(String(localized: "micros.more", defaultValue: "+\(nutrients.count - 4) more")).font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                        }
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ProfilePalette.muted).padding(.leading, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Group (the Expo `micro-group/[key].tsx`)

struct MicroGroupView: View {
    let groupKey: String
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model = NutritionScreenModel()

    private var group: NutrientCatalog.Group? { NutrientCatalog.GroupKey(rawValue: groupKey).map(NutrientCatalog.group) }

    var body: some View {
        VStack(spacing: 0) {
            NutritionHeader(title: group?.name ?? String(localized: "micros.title", defaultValue: "Micronutrients"))
            if let group {
                ScrollView(showsIndicators: false) {
                    if !model.loaded {
                        FALoadingState().padding(.top, 60)
                    } else {
                        let consumed = model.consumedToday
                        let nutrients = NutrientCatalog.nutrients(in: group.key)
                        let avg = nutrients.isEmpty ? 0 : Int((nutrients.reduce(0.0) { $0 + Double(NutritionMath.coveragePercent(consumed: consumed[$1.key] ?? 0, target: $1.target(sex: model.sex))) } / Double(nutrients.count)).rounded())
                        let gaps = nutrients.filter { NutritionMath.coveragePercent(consumed: consumed[$0.key] ?? 0, target: $0.target(sex: model.sex)) < 75 }.count
                        VStack(alignment: .leading, spacing: 0) {
                            overview(group: group, avg: avg, count: nutrients.count, gaps: gaps).padding(.bottom, 20)
                            Text(String(localized: "micros.nutrients", defaultValue: "Nutrients").uppercased())
                                .font(FATypography.sans(13, .bold, relativeTo: .caption)).tracking(0.4).foregroundStyle(ProfilePalette.muted).padding(.bottom, 10)
                            ForEach(nutrients) { n in
                                NutrientRow(nutrient: n, consumed: consumed[n.key] ?? 0, target: n.target(sex: model.sex), color: group.color) { router.push(.microNutrient(n.key)) }
                                    .padding(.bottom, 10)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, FASpacing.navBarClearance)
                    }
                }
            } else {
                Spacer()
                Text(String(localized: "micros.group.missing", defaultValue: "Group not found")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                Spacer()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load(dependencies) }
    }

    /// The tinted overview panel: glass (the rule) with the group's colour on the ring, figures and border.
    private func overview(group: NutrientCatalog.Group, avg: Int, count: Int, gaps: Int) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(avg)%").font(FATypography.display(28, relativeTo: .title)).foregroundStyle(group.color)
                        Text(String(localized: "micros.avgCoverage", defaultValue: "average coverage")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(localized: "micros.count", defaultValue: "\(count) nutrients")).font(FATypography.sans(13, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.ink)
                        if gaps > 0 {
                            Text(String(localized: "micros.belowTarget", defaultValue: "\(gaps) below target")).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(CoverageTone.red)
                        }
                    }
                }
                Text(group.description).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 12)
                Text(String(localized: "micros.why", defaultValue: "Why it matters").uppercased()).font(FATypography.sans(12, .bold, relativeTo: .caption)).tracking(0.4).foregroundStyle(FAColor.ink).padding(.top, 14)
                Text(group.whyItMatters).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 4)
                Text(String(localized: "micros.topFoods", defaultValue: "Top foods").uppercased()).font(FATypography.sans(12, .bold, relativeTo: .caption)).tracking(0.4).foregroundStyle(FAColor.ink).padding(.top, 14)
                Text(group.topFoods).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted).lineSpacing(4).padding(.top, 4)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous).strokeBorder(group.color.opacity(0.35), lineWidth: 1) }
    }
}

/// One nutrient in a group: badge, name, percent, a thin bar, "consumed · target", the tagline.
private struct NutrientRow: View {
    let nutrient: NutrientCatalog.Nutrient
    let consumed: Double
    let target: Double
    let color: Color
    let onTap: () -> Void

    var body: some View {
        let pct = NutritionMath.coveragePercent(consumed: consumed, target: target)
        let bar = CoverageTone.color(pct)
        Button(action: onTap) {
            FACard(padded: false) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        MoleculeBadge(nutrient: nutrient, color: color, size: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(nutrient.name).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                                Spacer()
                                Text("\(pct)%").font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(bar)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(ProfilePalette.surfaceSoft)
                                    Capsule().fill(bar).frame(width: geo.size.width * CGFloat(min(pct, 100)) / 100)
                                }
                            }
                            .frame(height: 5)
                            Text("\(NutrientFormat.amount(consumed))\(nutrient.unit) · \(String(localized: "micros.target", defaultValue: "target")) \(NutrientFormat.amount(target))\(nutrient.unit)")
                                .font(FATypography.sans(11, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(ProfilePalette.muted)
                    }
                    Text(nutrient.tagline).font(FATypography.sans(12, relativeTo: .caption)).foregroundStyle(ProfilePalette.muted).padding(.leading, 52)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Nutrient (the Expo `micro-nutrient/[key].tsx`)

struct MicroNutrientView: View {
    let nutrientKey: String
    @Environment(AppDependencies.self) private var dependencies
    @State private var model = NutritionScreenModel()

    private var nutrient: NutrientCatalog.Nutrient? { NutrientCatalog.nutrient(nutrientKey) }

    var body: some View {
        VStack(spacing: 0) {
            NutritionHeader(title: nutrient?.name ?? String(localized: "micros.title", defaultValue: "Micronutrients"))
            if let nutrient {
                ScrollView(showsIndicators: false) {
                    if !model.loaded {
                        FALoadingState().padding(.top, 60)
                    } else {
                        let group = NutrientCatalog.group(nutrient.groupKey)
                        let consumed = model.consumedToday[nutrient.key] ?? 0
                        let target = nutrient.target(sex: model.sex)
                        let pct = NutritionMath.coveragePercent(consumed: consumed, target: target)
                        let series = model.dailySeries(nutrientKey: nutrient.key, days: 7)
                        VStack(alignment: .leading, spacing: 12) {
                            heroCard(nutrient: nutrient, color: group.color, consumed: consumed, target: target, pct: pct, series: series.map(\.value))
                            trendCard(color: group.color, series: series)
                            sourcesCard(nutrient: nutrient, color: group.color)
                            if !nutrient.deficiencySymptoms.isEmpty { symptomsCard(nutrient: nutrient) }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, FASpacing.navBarClearance)
                    }
                }
            } else {
                Spacer()
                Text(String(localized: "micros.nutrient.missing", defaultValue: "Nutrient not found")).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                Spacer()
            }
        }
        .faWall()
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load(dependencies) }
    }

    private enum TrendDirection { case up, down, stable }

    private func direction(_ values: [Double]) -> TrendDirection {
        guard values.count >= 2 else { return .stable }
        let weekAvg = values.reduce(0, +) / Double(values.count)
        let recent = (values[values.count - 1] + values[values.count - 2]) / 2
        if recent > weekAvg * 1.05 { return .up }
        if recent < weekAvg * 0.95 { return .down }
        return .stable
    }

    private func heroCard(nutrient: NutrientCatalog.Nutrient, color: Color, consumed: Double, target: Double, pct: Int, series: [Double]) -> some View {
        let dir = direction(series)
        let tone: Color = dir == .up ? Color(hex: 0x059669) : dir == .down ? CoverageTone.red : ProfilePalette.muted
        let word = dir == .up ? String(localized: "micros.trend.up", defaultValue: "Improving this week") : dir == .down ? String(localized: "micros.trend.down", defaultValue: "Trending down") : String(localized: "micros.trend.stable", defaultValue: "Stable this week")
        let symbol = dir == .up ? "arrow.up.right" : dir == .down ? "arrow.down.right" : "minus"
        return FACard {
            ZStack {
                MoleculeBackdrop(nutrient: nutrient, color: color)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 20) {
                        CoverageRing(pct: pct, size: 100, strokeWidth: 8, color: CoverageTone.color(pct), subLabel: String(localized: "micros.ofTarget", defaultValue: "of target"))
                        VStack(alignment: .leading, spacing: 2) {
                            MicroLabel(text: String(localized: "micros.today", defaultValue: "Today"))
                            Text("\(NutrientFormat.amount(consumed))\(nutrient.unit)").font(FATypography.sans(26, .bold, relativeTo: .title)).foregroundStyle(FAColor.ink)
                            Text("\(String(localized: "micros.target", defaultValue: "target")): \(NutrientFormat.amount(target))\(nutrient.unit)").font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(ProfilePalette.muted)
                            HStack(spacing: 5) {
                                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                                Text(word).font(FATypography.sans(12, .semibold, relativeTo: .caption))
                            }
                            .foregroundStyle(tone).padding(.top, 8)
                        }
                    }
                    Text(nutrient.description).font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineSpacing(5)
                        .padding(.top, 14).overlay(alignment: .top) { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) }.padding(.top, 16)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FACornerRadius.glass, style: .continuous))
    }

    private func trendCard(color: Color, series: [(day: Date, value: Double)]) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel(text: String(localized: "micros.weekTrend", defaultValue: "7-day trend")).padding(.bottom, 14)
                SparkLine(values: series.map(\.value), color: color).frame(height: 44).frame(maxWidth: .infinity)
                HStack {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                        VStack(spacing: 2) {
                            Text(point.day.formatted(.dateTime.weekday(.abbreviated))).font(FATypography.sans(9, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
                            Text(NutrientFormat.amount(point.value)).font(FATypography.sans(10, .semibold, relativeTo: .caption2)).foregroundStyle(FAColor.ink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func sourcesCard(nutrient: NutrientCatalog.Nutrient, color: Color) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel(text: String(localized: "micros.sources", defaultValue: "Best food sources")).padding(.bottom, 4)
                ForEach(Array(nutrient.foodSources.enumerated()), id: \.offset) { i, source in
                    HStack(spacing: 12) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(source.food).font(FATypography.sans(14, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                        Spacer()
                        Text(source.amount).font(FATypography.sans(12, .bold, relativeTo: .caption)).foregroundStyle(color)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { if i < nutrient.foodSources.count - 1 { Rectangle().fill(ProfilePalette.hairline).frame(height: 1) } }
                }
            }
        }
    }

    private func symptomsCard(nutrient: NutrientCatalog.Nutrient) -> some View {
        FACard {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel(text: String(localized: "micros.symptoms", defaultValue: "Low-level deficiency signs"), color: CoverageTone.amber)
                FlowLayout(spacing: 8) {
                    ForEach(nutrient.deficiencySymptoms, id: \.self) { s in
                        Text(NutrientCatalog.symptomLabel(s)).font(FATypography.sans(12, .semibold, relativeTo: .caption)).foregroundStyle(CoverageTone.amber)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(CoverageTone.amber.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                Text(String(localized: "micros.symptoms.note", defaultValue: "These symptoms can have many causes. This is educational · not a diagnosis.")).font(FATypography.sans(10, relativeTo: .caption2)).foregroundStyle(ProfilePalette.muted)
            }
        }
    }
}

/// The Expo `SparkLine`: a polyline scaled to the max value, 3 pt of headroom.
struct SparkLine: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let maxV = max(values.max() ?? 1, 1)
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = values.count > 1 ? CGFloat(i) / CGFloat(values.count - 1) * w : w / 2
                    let y = h - CGFloat(v / maxV) * (h - 6) - 3
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
