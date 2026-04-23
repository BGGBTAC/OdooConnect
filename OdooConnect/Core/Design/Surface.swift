import SwiftUI

/// Five distinct card treatments, applied via `.cardSurface(.hero|...)`.
/// Built deliberately so cards visibly differ in prominence — every card
/// being the same `glassEffect(.regular, in: .rect(cornerRadius: 16))`
/// was the single biggest source of visual monotony in the old UI.
enum SurfaceStyle {
    /// Subtle ember-tinted glass for the one most-important card on a
    /// screen (e.g. dashboard revenue spotlight, product detail price).
    /// Body text stays the regular foreground so it's readable.
    case hero
    /// Standard liquid glass card. Sections, KPIs, list groupings.
    case standard
    /// Lightweight slate-tinted background. Inline groupings, sub-cards
    /// inside a standard card, secondary metadata blocks.
    case inset
    /// Standard liquid glass tinted with the brand colour. For surfaces
    /// that should read as "primary action" or "this is the brand bit".
    case branded
    /// Full-bleed brand banner with white text — login hero, splash, the
    /// occasional showcase moment. Use sparingly.
    case banner
}

struct CardSurface: ViewModifier {
    let style: SurfaceStyle

    func body(content: Content) -> some View {
        switch style {
        case .hero:
            content
                .padding(Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.heroGradient, in: .rect(cornerRadius: Radius.hero))
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.hero))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.hero)
                        .stroke(Theme.brand.opacity(0.20), lineWidth: 1)
                )
        case .standard:
            content
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.standard))
        case .inset:
            content
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.slate.opacity(0.08), in: .rect(cornerRadius: Radius.inset))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.inset)
                        .stroke(Theme.slate.opacity(0.15), lineWidth: 0.5)
                )
        case .branded:
            content
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(Theme.brand.opacity(0.16)),
                             in: .rect(cornerRadius: Radius.standard))
        case .banner:
            content
                .padding(Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bannerGradient, in: .rect(cornerRadius: Radius.banner))
                .foregroundStyle(.white)
                .shadow(color: Theme.brand.opacity(0.45), radius: 30, x: 0, y: 14)
        }
    }
}

extension View {
    func cardSurface(_ style: SurfaceStyle = .standard) -> some View {
        modifier(CardSurface(style: style))
    }
}
