import Foundation
import Observation

/// One pickable line shown in the picking UI. Combines stock.move.line
/// data with display info (image / variant) so the camera overlay can
/// show "Red T-Shirt L · 1/2" while the user scans.
struct PickableLine: Identifiable, Sendable, Equatable {
    let moveLineId: Int
    let productId: Int
    let displayName: String
    let barcode: String?
    let defaultCode: String?
    let demand: Double
    var picked: Double
    let uomName: String

    var id: Int { moveLineId }
    var remaining: Double { max(0, demand - picked) }
    var isComplete: Bool { picked >= demand }
    var progress: Double { demand > 0 ? min(1, picked / demand) : 0 }
}

@Observable
@MainActor
final class OrderPickingViewModel {
    let pickingId: Int
    let pickingName: String

    var lines: [PickableLine] = []
    var currentCarrier: Many2One?
    var availableCarriers: [DeliveryCarrier] = []
    var isLoading: Bool = false
    var isCommitting: Bool = false
    var error: String?
    var lastScanFlash: ScanFlash?

    /// Brief confirmation flash shown over the camera. Auto-clears
    /// after ~1.6 s via the view.
    struct ScanFlash: Equatable, Sendable {
        enum Kind: Sendable { case picked, alreadyDone, notInOrder, lookupFailed }
        let id: UUID = UUID()
        let kind: Kind
        let title: String
        let subtitle: String
    }

    init(pickingId: Int, pickingName: String) {
        self.pickingId = pickingId
        self.pickingName = pickingName
    }

    var totalDemand: Double { lines.reduce(0) { $0 + $1.demand } }
    var totalPicked: Double { lines.reduce(0) { $0 + $1.picked } }
    var allPicked: Bool { !lines.isEmpty && lines.allSatisfy(\.isComplete) }

    // MARK: - Loading

    func load(using client: OdooClient?) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            // 1. Fetch the picking to get carrier + name.
            let pickings: [StockPicking] = try await client.searchRead(
                model: "stock.picking",
                domain: [.array([.string("id"), .string("="), .int(pickingId)])],
                fields: StockPicking.fields,
                limit: 1
            )
            currentCarrier = pickings.first?.carrier_id

            // 2. Fetch the move lines + their products in one batch.
            let raw: [PickingLineDTO] = try await client.searchRead(
                model: "stock.move.line",
                domain: [.array([.string("picking_id"), .string("="), .int(pickingId)])],
                fields: PickingLineDTO.fields,
                limit: 500,
                order: "id asc"
            )
            let productIds = Array(Set(raw.compactMap { $0.product_id.id > 0 ? $0.product_id.id : nil }))
            let products: [PickingProductDTO] = productIds.isEmpty ? [] : try await client.searchRead(
                model: "product.product",
                domain: [.array([.string("id"), .string("in"), .array(productIds.map { .int($0) })])],
                fields: PickingProductDTO.fields,
                limit: productIds.count
            )
            let productById: [Int: PickingProductDTO] = Dictionary(
                products.map { ($0.id, $0) },
                uniquingKeysWith: { a, _ in a }
            )
            lines = raw.map { dto in
                let p = productById[dto.product_id.id]
                return PickableLine(
                    moveLineId: dto.id,
                    productId: dto.product_id.id,
                    displayName: p?.display_name ?? dto.product_id.name,
                    barcode: p?.barcode,
                    defaultCode: p?.default_code,
                    demand: dto.reserved_uom_qty ?? dto.quantity_demand ?? dto.quantity ?? 0,
                    picked: dto.quantity ?? dto.qty_done ?? 0,
                    uomName: dto.product_uom_id?.name ?? "Stk"
                )
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadCarriers(using client: OdooClient?) async {
        guard let client else { return }
        do {
            availableCarriers = try await client.searchRead(
                model: "delivery.carrier",
                domain: [.array([.string("active"), .string("="), .bool(true)])],
                fields: DeliveryCarrier.fields,
                limit: 100,
                order: "name asc"
            )
        } catch {
            // Carrier list is optional — silently absent if delivery
            // module isn't installed.
            availableCarriers = []
        }
    }

    // MARK: - Scanning

    /// Match a scanned barcode against open lines. Increments the
    /// matched line's quantity by 1 (in product UoM); if the product
    /// barcode happens to match a closed line, surface a "already
    /// picked" hint instead.
    func handleScan(_ code: String) {
        // Prefer an open line whose product barcode matches.
        if let openIdx = lines.firstIndex(where: { $0.barcode == code && !$0.isComplete }) {
            lines[openIdx].picked += 1
            let line = lines[openIdx]
            lastScanFlash = ScanFlash(
                kind: .picked,
                title: line.displayName,
                subtitle: "\(formatted(line.picked)) / \(formatted(line.demand)) \(line.uomName)"
            )
            return
        }
        if lines.contains(where: { $0.barcode == code && $0.isComplete }) {
            lastScanFlash = ScanFlash(
                kind: .alreadyDone,
                title: "Bereits vollständig gepickt",
                subtitle: code
            )
            return
        }
        lastScanFlash = ScanFlash(
            kind: .notInOrder,
            title: "Nicht in dieser Lieferung",
            subtitle: code
        )
    }

    /// Manual override for a row (typed quantity). Clamps to demand.
    func setQuantity(_ qty: Double, for lineId: Int) {
        guard let idx = lines.firstIndex(where: { $0.moveLineId == lineId }) else { return }
        lines[idx].picked = max(0, min(qty, lines[idx].demand))
    }

    func clearFlash() {
        lastScanFlash = nil
    }

    // MARK: - Commit

    /// Push the picked quantities + carrier choice to Odoo and validate.
    /// Returns a user-facing message describing the result; the caller
    /// can show it as a banner / alert.
    func commit(using client: OdooClient?, selectedCarrier: DeliveryCarrier?) async -> String? {
        guard let client else { return nil }
        isCommitting = true
        defer { isCommitting = false }
        do {
            // 1. Persist quantities for each move line. Try the modern
            // `quantity` field first; fall back to `qty_done` for older
            // Odoo if the write rejects.
            for line in lines {
                let value: JSON = .double(line.picked)
                do {
                    _ = try await client.write(
                        model: "stock.move.line",
                        ids: [line.moveLineId],
                        values: ["quantity": value]
                    )
                } catch {
                    _ = try await client.write(
                        model: "stock.move.line",
                        ids: [line.moveLineId],
                        values: ["qty_done": value]
                    )
                }
            }

            // 2. Update carrier if changed.
            if let selected = selectedCarrier, selected.id != currentCarrier?.id {
                _ = try await client.write(
                    model: "stock.picking",
                    ids: [pickingId],
                    values: ["carrier_id": .int(selected.id)]
                )
            }

            // 3. Validate the picking.
            let result: JSON = try await client.callKw(
                model: "stock.picking",
                method: "button_validate",
                args: [.array([.int(pickingId)])]
            )

            if case .object(let dict) = result,
               case .string(let model)? = dict["res_model"] {
                if model == "stock.backorder.confirmation" {
                    return "Backorder-Wizard erforderlich — bitte in der App-Web-Ansicht abschließen."
                }
                return "Odoo erwartet zusätzlichen Wizard (\(model))."
            }
            return "Lieferung versendet."
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    private func formatted(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rounded)
            : String(format: "%.2f", rounded)
    }
}

// MARK: - DTOs

private struct PickingLineDTO: Decodable, Sendable {
    let id: Int
    let product_id: Many2One
    let product_uom_id: Many2One?
    let quantity: Double?            // Odoo 18+: qty done
    let qty_done: Double?            // Odoo ≤17: qty done
    let reserved_uom_qty: Double?    // Odoo ≤17 demand
    let quantity_demand: Double?     // Odoo 18+ demand alias

    static let fields: [String] = [
        "id", "product_id", "product_uom_id",
        "quantity", "qty_done", "reserved_uom_qty"
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        product_id = try c.decode(Many2One.self, forKey: .product_id)
        product_uom_id = try? c.decode(Many2One.self, forKey: .product_uom_id)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        qty_done = try c.decodeIfPresent(Double.self, forKey: .qty_done)
        reserved_uom_qty = try c.decodeIfPresent(Double.self, forKey: .reserved_uom_qty)
        quantity_demand = nil
    }

    enum CodingKeys: String, CodingKey {
        case id, product_id, product_uom_id, quantity, qty_done, reserved_uom_qty
    }
}

private struct PickingProductDTO: Decodable, Sendable {
    let id: Int
    let display_name: String
    @OdooOptionalString var barcode: String?
    @OdooOptionalString var default_code: String?

    static let fields: [String] = ["id", "display_name", "barcode", "default_code"]
}
