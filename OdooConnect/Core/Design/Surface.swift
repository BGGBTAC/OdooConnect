import SwiftUI

/// Content-card treatments, applied via `.cardSurface(.hero|...)`.
///
/// iOS 26 design rule (Apple HIG / WWDC25): Liquid Glass belongs to the
/// floating navigation/control layer (tab bar, toolbars, sheets, buttons)
/// and must NOT be applied to content (cards, lists, charts). So these
/// surfaces are now OPAQUE system backgrounds with concentric-friendly
/// radii — no glass, no custom shadows, no strokes. Prominence is conveyed
/// by a subtle brand tint and padding, not by chrome.
enum SurfaceStyle {
    /// The one most-important card on a screen (dashboard revenue spotlight,
    /// product price). A faint brand wash over the card fill.
    case hero
    /// Standard content card. Sections, KPIs, list groupings.
    case standard
    /// Lightweight sub-surface. Inline groupings, sub-cards, metadata blocks.
    case inset
    /// Brand-tinted content surface — reads as "this is the brand bit".
    case branded
    /// Full-bleed brand banner with white text — login hero / splash only.
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
                .background(Theme.brand.opacity(0.08), in: .rect(cornerRadius: Radius.hero))
                .background(Theme.cardFill, in: .rect(cornerRadius: Radius.hero))
        case .standard:
            content
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardFill, in: .rect(cornerRadius: Radius.standard))
        case .inset:
            content
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.insetFill, in: .rect(cornerRadius: Radius.inset))
        case .branded:
            content
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brand.opacity(0.12), in: .rect(cornerRadius: Radius.standard))
                .background(Theme.cardFill, in: .rect(cornerRadius: Radius.standard))
        case .banner:
            content
                .padding(Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bannerGradient, in: .rect(cornerRadius: Radius.banner))
                .foregroundStyle(.white)
        }
    }
}

extension View {
    func cardSurface(_ style: SurfaceStyle = .standard) -> some View {
        modifier(CardSurface(style: style))
    }

    /// Opaque content-card background — the drop-in replacement for the old
    /// `.glassEffect(.regular, in: .rect(cornerRadius:))` on content cards.
    /// (Glass is reserved for the navigation/control layer on iOS 26.)
    func contentCard(cornerRadius: CGFloat = Radius.standard) -> some View {
        background(Theme.cardFill, in: .rect(cornerRadius: cornerRadius))
    }
}
