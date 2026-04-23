import SwiftUI

/// Branded replacement for the default `ContentUnavailableView`. Same
/// shape, same accessibility behaviour, but the icon sits on a tinted
/// circle in the brand colour so empty screens still feel like the app.
struct BrandedEmptyState: View {
    let title: String
    let systemImage: String
    let message: String?

    init(title: String, systemImage: String, message: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.brand.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.brand)
            }
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
