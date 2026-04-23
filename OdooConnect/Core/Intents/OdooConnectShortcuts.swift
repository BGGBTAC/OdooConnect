import AppIntents

/// Wires our intents into Siri voice phrases, the Shortcuts app, and the
/// CarPlay Siri overlay. Phrases must contain `\(.applicationName)` per
/// Apple's rules — the system substitutes "OdooCompanion" at runtime.
struct OdooConnectShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayRevenueIntent(),
            phrases: [
                "Tagesumsatz in \(.applicationName)",
                "Wie viel Umsatz heute in \(.applicationName)",
                "Heutiger Umsatz mit \(.applicationName)"
            ],
            shortTitle: "Tagesumsatz",
            systemImageName: "eurosign.circle.fill"
        )

        AppShortcut(
            intent: OpenOrdersTodayIntent(),
            phrases: [
                "Neue Bestellungen in \(.applicationName)",
                "Wie viele Bestellungen heute in \(.applicationName)",
                "Bestellungen heute mit \(.applicationName)"
            ],
            shortTitle: "Bestellungen heute",
            systemImageName: "cart.fill"
        )

        AppShortcut(
            intent: StockLookupIntent(),
            phrases: [
                "Lagerbestand in \(.applicationName)",
                "Bestand prüfen mit \(.applicationName)",
                "Frag \(.applicationName) nach dem Bestand"
            ],
            shortTitle: "Bestand prüfen",
            systemImageName: "shippingbox.fill"
        )
    }

    /// Tile color in the Shortcuts app. Match the app brand.
    static let shortcutTileColor: ShortcutTileColor = .orange
}
