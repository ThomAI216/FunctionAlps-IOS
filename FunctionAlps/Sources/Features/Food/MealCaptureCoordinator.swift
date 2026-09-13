import PhotosUI
import SwiftUI

/// One tap from any "photo" affordance (Home square, Food hero) to the phone's own chooser,
/// and the full-screen capture flow after it. Shared by Home and Food so the number of steps
/// between wanting to log a meal and seeing the camera is decided in exactly one place.
@MainActor
@Observable
final class MealCaptureCoordinator {
    var showPhotoSource = false
    var showCamera = false
    var showLibrary = false
    var libraryItems: [PhotosPickerItem] = []
    var request: CaptureRequest?
    var error: String?
    /// Two or more photos picked: the grouping question, up until it is answered.
    var grouping: PhotoGroup?
    private(set) var loadingPhotos = false

    struct PhotoGroup: Identifiable, Sendable {
        let id = UUID()
        let photos: [Data]
    }
    /// "A whole day": the review cover, while it is up.
    var dayBatch: PhotoGroup?

    /// A WHOLE DAY: every photo becomes its own row up front and the member sets the slot per photo.
    func wholeDay(_ photos: [Data]) {
        grouping = nil
        guard !photos.isEmpty else { return }
        dayBatch = PhotoGroup(photos: photos)
    }

    func openPhotoChooser() { showPhotoSource = true }

    func begin(_ input: MealCaptureInput) {
        guard !input.isEmpty else { return }
        request = CaptureRequest(input: input)
    }

    func picked(_ image: UIImage) {
        guard let jpeg = MealImage.jpeg(image) else {
            error = String(localized: "food.photo.unreadable", defaultValue: "That photo couldn't be read. Try another one.")
            return
        }
        begin(MealCaptureInput(photos: [jpeg], source: .photo))
    }

    /// The library's multi-select landed. One photo goes straight in; two or more raise the grouping question.
    func pickedMany(_ jpegs: [Data]) {
        switch MealPhotoGrouping.choice(for: jpegs.count) {
        case .single:
            guard let only = jpegs.first else {
                error = String(localized: "food.photo.unreadable", defaultValue: "That photo couldn't be read. Try another one.")
                return
            }
            begin(MealCaptureInput(photos: [only], source: .photo))
        case .ask:
            grouping = PhotoGroup(photos: jpegs)
        }
    }

    /// ONE MEAL, SEVERAL PHOTOS: photo 1 is the hero and the rest ride along to the same analyse call and the
    /// same row. Capped at what the model is handed.
    func oneMeal(_ photos: [Data]) {
        grouping = nil
        guard MealPhotoGrouping.oneMealAllowed(photos.count) else { return }
        begin(MealCaptureInput(photos: Array(photos.prefix(MealPhotoGrouping.maxPerMeal)), source: .photo))
    }

    /// ONE MEAL PER PHOTO: the first is captured now, the rest are queued behind it in the same cover.
    func separateMeals(_ photos: [Data]) {
        grouping = nil
        guard let first = photos.first else { return }
        var r = CaptureRequest(input: MealCaptureInput(photos: [first], source: .photo))
        r.queue = Array(photos.dropFirst())
        r.total = photos.count
        request = r
    }

    /// Loads every picked item off the main actor's way, re-encoding each (downscale, strip EXIF).
    func loadPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        loadingPhotos = true
        defer { loadingPhotos = false; libraryItems = [] }
        var jpegs: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = MealImage.jpeg(image) {
                jpegs.append(jpeg)
            }
        }
        if jpegs.count < items.count, jpegs.isEmpty {
            error = String(localized: "food.photo.unreadable", defaultValue: "That photo couldn't be read. Try another one.")
            return
        }
        pickedMany(jpegs)
    }
}

/// Attaches the chooser, the camera, the library picker, the capture cover and the error alert.
struct MealCaptureHost: ViewModifier {
    @Bindable var coordinator: MealCaptureCoordinator
    let onFinished: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $coordinator.showPhotoSource) {
                PhotoSourceSheet(
                    cameraAvailable: CameraPicker.isAvailable,
                    onCamera: { coordinator.showPhotoSource = false; coordinator.showCamera = true },
                    onLibrary: { coordinator.showPhotoSource = false; coordinator.showLibrary = true }
                )
                .presentationDetents([.height(CameraPicker.isAvailable ? 250 : 190)])
                .presentationBackground(.clear)
                .presentationDragIndicator(.hidden)
                .preferredColorScheme(.light)
            }
            .fullScreenCover(isPresented: $coordinator.showCamera) {
                CameraPicker { image in coordinator.picked(image) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $coordinator.showLibrary, selection: $coordinator.libraryItems, maxSelectionCount: MealPhotoGrouping.maxSelection, matching: .images)
            .onChange(of: coordinator.libraryItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await coordinator.loadPicked(items) }
            }
            .sheet(item: $coordinator.grouping) { group in
                PhotoGroupingSheet(
                    photos: group.photos,
                    onOneMeal: { coordinator.oneMeal(group.photos) },
                    onSeparateMeals: { coordinator.separateMeals(group.photos) },
                    onWholeDay: { coordinator.wholeDay(group.photos) },
                    onCancel: { coordinator.grouping = nil }
                )
                .presentationDetents([.height(MealPhotoGrouping.oneMealAllowed(group.photos.count) ? 428 : 460)])
                .presentationBackground(.clear)
                .presentationDragIndicator(.hidden)
                .preferredColorScheme(.light)
            }
            .fullScreenCover(item: $coordinator.dayBatch) { batch in
                DayReviewView(photos: batch.photos) {
                    coordinator.dayBatch = nil
                    onFinished()
                }
            }
            .fullScreenCover(item: $coordinator.request) { request in
                CaptureView(request: request) {
                    coordinator.request = nil
                    onFinished()
                }
            }
            .alert(String(localized: "food.photo.errorTitle", defaultValue: "Photo"), isPresented: Binding(get: { coordinator.error != nil }, set: { if !$0 { coordinator.error = nil } })) {
                Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {}
            } message: {
                Text(coordinator.error ?? "")
            }
    }
}

extension View {
    func mealCaptureHost(_ coordinator: MealCaptureCoordinator, onFinished: @escaping () -> Void) -> some View {
        modifier(MealCaptureHost(coordinator: coordinator, onFinished: onFinished))
    }
}

/// "Add your meal by photo" — the app's own light glass chooser, never the system dialog (which
/// takes whatever appearance the system feels like; the owner wants the see-through light glass).
struct PhotoSourceSheet: View {
    let cameraAvailable: Bool
    let onCamera: () -> Void
    let onLibrary: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Text(String(localized: "food.photo.title", defaultValue: "Add your meal by photo"))
                .font(FATypography.display(19, relativeTo: .title3))
                .foregroundStyle(FAColor.ink)
                .padding(.top, 6)
                .padding(.bottom, 4)
            if cameraAvailable {
                option(symbol: "camera", title: String(localized: "food.photo.camera", defaultValue: "Take a photo"), action: onCamera)
            }
            option(symbol: "photo.on.rectangle", title: String(localized: "food.photo.library", defaultValue: "Choose from library"), action: onLibrary)
            Button { dismiss() } label: {
                Text(String(localized: "common.cancel", defaultValue: "Cancel"))
                    .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(FAColor.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .modifier(FAGlassSurface(cornerRadius: FACornerRadius.glass))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func option(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(FAColor.forestSoft).frame(width: 22)
                Text(title).font(FATypography.sans(15, .semibold, relativeTo: .body)).foregroundStyle(FAColor.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(FAColor.inkSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "Is this one meal with several plates, or several separate meals?" — asked once, right after picking.
/// "One meal" is greyed above the model's cap with the reason written out; "separate" is always offered.
struct PhotoGroupingSheet: View {
    let photos: [Data]
    let onOneMeal: () -> Void
    let onSeparateMeals: () -> Void
    var onWholeDay: () -> Void = {}
    let onCancel: () -> Void

    private var combinable: Bool { MealPhotoGrouping.oneMealAllowed(photos.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "food.grouping.title", defaultValue: "\(photos.count) photos"))
                .font(FATypography.display(20, relativeTo: .title3)).foregroundStyle(FAColor.ink)
            Text(String(localized: "food.grouping.question", defaultValue: "Is this one meal with several plates, or several separate meals?"))
                .font(FATypography.sans(13, relativeTo: .subheadline)).foregroundStyle(FAColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(.top, 8)
            Button(action: onOneMeal) {
                Text(String(localized: "food.grouping.oneMeal", defaultValue: "One meal · several plates"))
                    .font(FATypography.sans(13.5, .bold, relativeTo: .subheadline)).foregroundStyle(FAColor.charcoal)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(FAColor.forestSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!combinable)
            .opacity(combinable ? 1 : 0.4)
            .padding(.top, 10)
            if !combinable {
                Text(String(localized: "food.grouping.tooMany", defaultValue: "More than \(MealPhotoGrouping.maxPerMeal) photos · log these as separate meals, or pick fewer for one meal."))
                    .font(FATypography.sans(11.5, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onSeparateMeals) {
                Text(String(localized: "food.grouping.separate", defaultValue: "Separate meals · one per photo"))
                    .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Button(action: onWholeDay) {
                Text(String(localized: "food.grouping.wholeDay", defaultValue: "A whole day · set the meal for each photo"))
                    .font(FATypography.sans(13.5, .semibold, relativeTo: .subheadline)).foregroundStyle(FAColor.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FAColor.separator, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Button(action: onCancel) {
                Text(String(localized: "common.cancel", defaultValue: "Cancel"))
                    .font(FATypography.sans(12.5, .semibold, relativeTo: .caption)).foregroundStyle(FAColor.inkSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .modifier(FAGlassSurface(cornerRadius: FACornerRadius.glass))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
