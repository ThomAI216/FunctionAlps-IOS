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
            .confirmationDialog(String(localized: "food.photo.title", defaultValue: "Add your meal by photo"), isPresented: $coordinator.showPhotoSource, titleVisibility: .visible) {
                if CameraPicker.isAvailable {
                    Button(String(localized: "food.photo.camera", defaultValue: "Take a photo")) { coordinator.showCamera = true }
                }
                Button(String(localized: "food.photo.library", defaultValue: "Choose from library")) { coordinator.showLibrary = true }
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
