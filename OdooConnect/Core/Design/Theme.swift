import SwiftUI

/// App-wide design tokens. Avoid `.accentColor`/`.tint` defaults inside
/// views — go through `Theme.brand` so we have one place to repaint the
/// whole app from. Values are tuned for both light & dark mode.
enum Theme {
    /// Ember orange — distinctive, energetic, signals movement through a
    /// logistics pipeline. Reads as "OdooCompanion", not "stock SwiftUI".
    static let brand = Color(red: 248/255, green: 113/255, blue: 32/255)
    /// Cool slate, used for neutral emphasis & secondary buttons.
    static let slate = Color(red: 100/255, green: 116/255, blue: 139/255)

    /// Semantic palette — use these everywhere instead of bare
    /// `.green` / `.red` / `.orange`. Especially: stop assigning a
    /// random hue to each KPI ("rainbow dashboard"). Map by *meaning*.
    static let success = Color(red: 16/255,  green: 185/255, blue: 129/255)  // emerald
    static let warning = Color(red: 251/255, green: 191/255, blue: 36/255)   // amber
    static let danger  = Color(red: 239/255, green: 68/255,  blue: 68/255)   // crimson
    static let info    = Color(red: 59/255,  green: 130/255, blue: 246/255)  // sky

    /// Subtle radial wash used as the dashboard background veil.
    static let pageVeil = LinearGradient(
        colors: [brand.opacity(0.06), .clear],
        startPoint: .top,
        endPoint: .center
    )

    /// Strong gradient for brand-banner moments (Login hero, splash, etc.).
    static let bannerGradient = LinearGradient(
        stops: [
            .init(color: brand,                       location: 0.0),
            .init(color: brand.opacity(0.85),         location: 0.6),
            .init(color: Color(red: 220/255, green: 70/255, blue: 20/255), location: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle hero gradient for KPI/spotlight cards — keeps the surface
    /// light enough that body text stays readable in light & dark mode.
    static let heroGradient = LinearGradient(
        colors: [brand.opacity(0.18), brand.opacity(0.04)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Spacing rhythm. Use these instead of hardcoded numbers.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 40
}

/// Corner radii — three distinct levels so cards visibly differ in
/// prominence instead of all being 16pt.
enum Radius {
    static let inset: CGFloat = 12
    static let standard: CGFloat = 16
    static let hero: CGFloat = 20
    static let banner: CGFloat = 28
}
