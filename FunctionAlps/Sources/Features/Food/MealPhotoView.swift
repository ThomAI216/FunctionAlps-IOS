import SwiftUI

/// A meal photo from the private bucket: signs the path on demand, caches the URL.
struct MealPhotoView: View {
    @Environment(AppDependencies.self) private var dependencies
    let path: String?
    var width: CGFloat? = 76
    var height: CGFloat = 76
    var cornerRadius: CGFloat = FACornerRadius.md
    @State private var url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(FAColor.surfaceMuted)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ProgressView().tint(FAColor.brand)
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(FAColor.separator, lineWidth: 1)
        }
        .task(id: path) {
            guard let path else { url = nil; return }
            url = try? await dependencies.meals.photoURL(path: path)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: min(height, 76) * 0.32))
            .foregroundStyle(FAColor.inkMuted)
    }
}
