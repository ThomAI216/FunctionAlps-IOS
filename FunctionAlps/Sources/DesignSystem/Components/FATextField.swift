import SwiftUI

struct FATextField: View {
    enum Kind { case email, password, text }

    let label: String
    @Binding var text: String
    var kind: Kind = .text
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: FASpacing.xs) {
            Text(label.uppercased())
                .font(FATypography.label)
                .foregroundStyle(FAColor.inkSecondary)
                .tracking(0.6)
            field
                .font(FATypography.body)
                .padding(.horizontal, FASpacing.md)
                .frame(minHeight: 50)
                .background(FAColor.surfaceOpaque, in: RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FACornerRadius.md, style: .continuous)
                        .strokeBorder(FAColor.separator, lineWidth: 1)
                }
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var field: some View {
        switch kind {
        case .email:
            TextField(label, text: $text)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .password:
            SecureField(label, text: $text)
                .textContentType(.password)
        case .text:
            TextField(label, text: $text)
        }
    }
}
