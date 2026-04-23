import AppIntents
import Foundation

/// "Hey Siri, frag OdooCompanion nach Bestand für [Produkt]" — looks
/// up a product by name, SKU, or barcode and reads back available
/// stock + forecast.
struct StockLookupIntent: AppIntent {
    static let title: LocalizedStringResource = "Lagerbestand prüfen"
    static let description = IntentDescription(
        "Sucht ein Produkt nach Name, Artikelnummer oder Barcode und liest den Lagerbestand vor.",
        categoryName: "Lager"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Produkt",
        description: "Name, Artikelnummer oder Barcode",
        requestValueDialog: IntentDialog("Welches Produkt soll ich nachschlagen?")
    )
    var productQuery: String

    static var parameterSummary: some ParameterSummary {
        Summary("Bestand für \(\.$productQuery)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let needle = productQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return .result(dialog: "Bitte einen Produktnamen oder Artikelnummer angeben.")
        }

        let client: OdooClient
        do {
            client = try IntentSession.requireClient()
        } catch {
            return .result(dialog: "Bitte erst in OdooCompanion anmelden.")
        }

        let products: [ProductDetail]
        do {
            products = try await client.searchRead(
                model: "product.product",
                domain: [
                    .string("|"), .string("|"),
                    .array([.string("name"), .string("ilike"), .string(needle)]),
                    .array([.string("default_code"), .string("ilike"), .string(needle)]),
                    .array([.string("barcode"), .string("="), .string(needle)])
                ],
                fields: ProductDetail.fields,
                limit: 5,
                order: "name asc"
            )
        } catch {
            return .result(dialog: "Odoo nicht erreichbar: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }

        guard let product = products.first else {
            return .result(dialog: "Kein Produkt gefunden für \(needle).")
        }

        let qty = Int(product.qty_available)
        let forecast = Int(product.virtual_available)
        let label = product.display_name

        let dialog: IntentDialog
        if products.count > 1 {
            dialog = "Mehrere Treffer. \(label): \(qty) auf Lager."
        } else if qty == forecast {
            dialog = "\(label): \(qty) auf Lager."
        } else if forecast > qty {
            let incoming = forecast - qty
            dialog = "\(label): \(qty) auf Lager, \(incoming) eingehend (Prognose \(forecast))."
        } else {
            let outgoing = qty - forecast
            dialog = "\(label): \(qty) auf Lager, \(outgoing) reserviert (Prognose \(forecast))."
        }
        return .result(dialog: dialog)
    }
}
