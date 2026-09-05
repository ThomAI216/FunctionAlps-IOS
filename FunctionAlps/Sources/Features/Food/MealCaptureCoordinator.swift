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
    var libraryItem: PhotosPickerItem?
    var request: CaptureRequest?
    var error: String?

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
            .photosPicker(isPresented: $coordinator.showLibrary, selection: $coordinator.libraryItem, matching: .images)
            .onChange(of: coordinator.libraryItem) { _, item in
                guard let item else { return }
                Task {
                    defer { coordinator.libraryItem = nil }
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        coordinator.picked(image)
                    } else {
                        coordinator.error = String(localized: "food.photo.unreadable", defaultValue: "That photo couldn't be read. Try another one.")
                    }
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
