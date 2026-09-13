import SwiftUI

// The correction surfaces around the meal page (the Expo `MealAdjustBar`, `MealItemsEditor`, `PhotoPortionReview`,
// `LearnedToast`) — one editable list underneath, rendered by `EditableItemList`.

/// The one control under the ingredient list, in its three states: re-analysis in flight, re-analysis failed,
/// or the invitation to adjust. Nothing at all until the meal has been priced (a dead button is not honest).
struct MealAdjustBar: View {
    @Bindable var model: MealEditModel

    var body: some View {
        if model.reanalyzing {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .semibold))
                Text(String(localized: "meal.edit.updating", defaultValue: "Updating nutrition…")).font(FATypography.sans(13, .bold, relativeTo: .subheadline))
            }
            .foregroundStyle(FAColor.forestSoft)
            .frame(maxWidth: .infinity).padding(.vertical, 11).padding(.top, 14)
        } else if let error = model.error {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 13, weight: .semibold))
                    Text(error).font(FATypography.sans(12, .semibold, relativeTo: .caption))
                }
                .foregroundStyle(Color(hex: 0xC0453A))
                HStack(spacing: 10) {
                    Button { Task { await model.updateNutrition() } } label: {
                        Text(String(localized: "action.tryAgain", defaultValue: "Try again")).font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(FoodPalette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    Button { model.error = nil; model.beginEdit() } label: {
                        Text(String(localized: "meal.edit.editItems", defaultValue: "Edit items")).font(FATypography.sans(12.5, .bold, relativeTo: .caption)).foregroundStyle(FoodPalette.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FoodPalette.hairline, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(hex: 0xC0453A, opacity: 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: 0xC0453A, opacity: 0.35), lineWidth: 1) }
            .padding(.top, 14)
        } else if model.canAdjust {
            Button { model.beginEdit() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold))
                    Text(String(localized: "meal.edit.adjust", defaultValue: "Adjust foods & portions")).font(FATypography.sans(13, .bold, relativeTo: .subheadline))
                }
                .foregroundStyle(FAColor.forestSoft)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(FoodPalette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }
}

/// Edit mode: one line per item (name · − grams + ·×), "Add item", "Update nutrition", Cancel / Save changes.
struct MealItemsEditor: View {
    @Bindable var model: MealEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditableItemList(
                items: model.rows,
                onRename: { model.rename($0, to: $1) },
                onGrams: { model.setGrams($0, $1) },
                onRemove: { model.remove($0) },
                onAdd: { model.add($0) }
            )
            Button { Task { await model.updateNutrition() } } label: {
                HStack(spacing: 8) {
                    if model.reanalyzing { ProgressView().tint(FAColor.forestSoft).scaleEffect(0.8) } else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .semibold)) }
                    Text(model.reanalyzing ? String(localized: "meal.edit.updating", defaultValue: "Updating nutrition…") : String(localized: "meal.edit.updateNutrition", defaultValue: "Update nutrition"))
                        .font(FATypography.sans(13, .bold, relativeTo: .subheadline))
                }
                .foregroundStyle(FAColor.forestSoft)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(FoodPalette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(model.reanalyzing)
            .opacity(model.reanalyzing ? 0.6 : 1)
            .padding(.top, 4)
            Text(String(localized: "meal.edit.hint", defaultValue: "Portions update instantly. Changed which food it is? Its nutrition updates a moment later · only that food, the rest stays put."))
                .font(FATypography.sans(10.5, relativeTo: .caption2)).foregroundStyle(FoodPalette.muted).padding(.horizontal, 4)
            if model.pricingCount > 0 {
                HStack(spacing: 7) {
                    ProgressView().tint(FAColor.forestSoft).scaleEffect(0.7)
                    Text(String(localized: "meal.edit.pricing", defaultValue: "Adding its calories & macros…")).font(FATypography.sans(11.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.forestSoft)
                }
                .padding(.horizontal, 4)
            }
            if let error = model.error {
                Text(error).font(FATypography.sans(11, .semibold, relativeTo: .caption)).foregroundStyle(Color(hex: 0xC0453A)).padding(.horizontal, 4)
            }
            HStack(spacing: 10) {
                Button { model.cancelEdit() } label: {
                    Text(String(localized: "action.cancel", defaultValue: "Cancel")).font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(FoodPalette.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FoodPalette.hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                Button { Task { await model.save() } } label: {
                    Text(String(localized: "meal.edit.save", defaultValue: "Save changes")).font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(FAColor.forestSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!model.dirty || model.reanalyzing)
                .opacity(model.dirty && !model.reanalyzing ? 1 : 0.5)
            }
            .padding(.top, 6)
        }
        .padding(.top, 4)
    }
}

/// The photo flow's mid-flight confirmation — household portions to point at, one chip per reference.
struct PhotoPortionReviewCard: View {
    @Bindable var model: PhotoReviewModel
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("◆ " + String(localized: "photoReview.kicker", defaultValue: "Check your portions").uppercased())
                .font(FATypography.sans(9.5, .bold, relativeTo: .caption2)).tracking(1.4).foregroundStyle(FAColor.forestSoft)
            Text(PhotoReview.copy(model.reason))
                .font(FATypography.sans(12.5, relativeTo: .caption)).foregroundStyle(FAColor.ink).lineSpacing(5).padding(.bottom, 4)
            EditableItemList(
                items: model.rows,
                onRename: { model.rename($0, to: $1) },
                // The wheel and the ± nudge are the EXACT-grams path; they clear the reference label because they are not one.
                onGrams: { model.setGrams($0, $1, label: nil) },
                onRemove: { model.remove($0) },
                onAdd: { model.add($0) }
            ) { index in
                portionChips(index)
            }
            Button(action: onConfirm) {
                HStack(spacing: 8) {
                    if model.pricing { ProgressView().tint(FAColor.charcoal).scaleEffect(0.8) } else { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                    Text(model.pricing
                         ? String(localized: "meal.edit.updating", defaultValue: "Updating nutrition…")
                         : model.unpricedCount > 0
                         ? String(localized: "photoReview.confirmUpdate", defaultValue: "Looks right · update nutrition")
                         : String(localized: "photoReview.confirm", defaultValue: "Looks right"))
                        .font(FATypography.sans(13.5, .bold, relativeTo: .subheadline))
                }
                .foregroundStyle(FAColor.charcoal)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(FAColor.forestSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.pricing)
            .opacity(model.pricing ? 0.6 : 1)
            .padding(.top, 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FoodPalette.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FAColor.forestSoft, lineWidth: 1) }
    }

    @ViewBuilder
    private func portionChips(_ index: Int) -> some View {
        if model.working.items.indices.contains(index) {
            let item = model.working.items[index]
            let options = PortionReference.options(for: item.name, estimatedGrams: item.estimatedGrams ?? 100)
            let current = PortionReference.selectedLabel(options, grams: item.estimatedGrams ?? 0)
            FlowLayout(spacing: 5) {
                ForEach(options, id: \.label) { opt in
                    let on = current == opt.label
                    Button { model.setGrams(index, Double(opt.grams), label: opt.label) } label: {
                        (Text(opt.localizedLabel).font(FATypography.sans(11, on ? .bold : .semibold, relativeTo: .caption)).foregroundColor(on ? .white : FAColor.ink)
                            + Text(" · \(opt.grams) g").font(FATypography.sans(11, relativeTo: .caption)).foregroundColor(on ? Color.white.opacity(0.85) : FoodPalette.muted))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(on ? FAColor.forestSoft : Color.white.opacity(0.7), in: Capsule())
                            .overlay { Capsule().strokeBorder(on ? FAColor.forestSoft : FoodPalette.hairline, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4).padding(.top, 5).padding(.bottom, 2)
        }
    }
}

/// "We'll remember that" — one thank-you toast naming the corrected food. Makes the learning VISIBLE.
struct LearnedToast: View {
    let food: String
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(FAColor.forestSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "meal.learned.title", defaultValue: "Got it · “\(EditableItemList<EmptyView>.capFirst(food))”")).font(FATypography.sans(13, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink).lineLimit(1)
                Text(String(localized: "meal.learned.body", defaultValue: "We’ll remember that next time.")).font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FoodPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .modifier(FAGlassSurface(cornerRadius: 14))
        .task {
            try? await Task.sleep(for: .seconds(3.2))
            onDone()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
