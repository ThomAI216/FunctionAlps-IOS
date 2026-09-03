import SwiftUI

struct FACard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(FASpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FACornerRadius.lg, style: .continuous))
            .background(FAColor.surface, in: RoundedRectangle(cornerRadius: FACornerRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FACornerRadius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
    }
}

struct FASection<Content: View>: View {
    let title: String
    var kicker: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: FASpacing.sm) {
            if let kicker {
                Text(kicker.uppercased())
                    .font(FATypography.label)
                    .foregroundStyle(FAColor.brand)
                    .tracking(0.8)
            }
            Text(title)
                .font(FATypography.title)
                .foregroundStyle(FAColor.ink)
            content
        }
    }
}

struct FAMetricCard: View {
    let label: String
    let value: String
    var caption: String? = nil

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: FASpacing.xs) {
                Text(label).font(FATypography.label).foregroundStyle(FAColor.inkSecondary)
                Text(value).font(FATypography.metric).foregroundStyle(FAColor.ink)
                if let caption {
                    Text(caption).font(FATypography.caption).foregroundStyle(FAColor.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FAListRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: FASpacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(FAColor.brand)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FATypography.body).foregroundStyle(FAColor.ink)
                if let subtitle {
                    Text(subtitle).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, FASpacing.xs)
        .contentShape(Rectangle())
    }
}

/// Placeholder brand mark until the real asset lands in Assets.xcassets.
struct FABrandMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(FAColor.brand)
            Image(systemName: "mountain.2.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
