import Foundation
import Observation

@Observable
@MainActor
final class DashboardViewModel {
    var period: DashboardPeriod = .mtd {
        didSet { if oldValue != period { Task { await loadPeriod() } } }
    }

    // Aggregate KPIs (all in one struct so the view animates coherently).
    var kpis: ShopKPIs = ShopKPIs()

    // Series & lists
    var revenueSeries: [RevenuePoint] = []
    var topProducts: [TopProductRow] = []
    var invoicePipeline: [InvoicePipelineBucket] = []
    var lowStock: [LowStockRow] = []
    var recentOrders: [SaleOrder] = []

    var isLoading: Bool = false
    var lastRefresh: Date?
    var error: String?

    private var client: OdooClient?

    func load(using client: OdooClient?) async {
        // Don't clobber a previously valid client with nil — when the
        // Dashboard is rebuilt before AuthManager has fully restored
        // (race between SwiftUI tree settling and Keychain restore),
        // `auth.client` can be nil for a tick. Keep what we have.
        if let client { self.client = client }
        await loadPeriod()
    }

    private func loadPeriod() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }

        let range = period.range()
        let previous = period.previousRange()

        // Primary KPIs: revenue + order count drive everything else and
        // their failure usually indicates a real problem (network down,
        // session expired). If they throw, keep the previously-rendered
        // numbers and surface the error — wiping to zero leaves the user
        // staring at a blank dashboard with no clue why, which is the
        // bug pull-to-refresh hit when a stale Task got cancelled.
        let revCurrent: Double
        let revPrevious: Double
        let ordCurrent: Int
        let ordPrevious: Int
        do {
            async let _revCurrent  = self.fetchRevenue(client, range: range)
            async let _revPrevious = self.fetchRevenue(client, range: previous)
            async let _ordCurrent  = self.fetchOrderCount(client, range: range)
            async let _ordPrevious = self.fetchOrderCount(client, range: previous)
            revCurrent  = try await _revCurrent
            revPrevious = try await _revPrevious
            ordCurrent  = try await _ordCurrent
            ordPrevious = try await _ordPrevious
        } catch is CancellationError {
            // Pull-to-refresh interrupted us. The next load will run.
            return
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        // Secondary fetches are individually resilient: a failure in
        // any one shouldn't blank the whole board. They run in parallel
        // and each gets a sensible empty default.
        async let newCustomers = safeDeltaInt { try await self.fetchNewCustomers(client, range: range) } previous: { try await self.fetchNewCustomers(client, range: previous) }
        async let cancelRate   = (try? self.fetchCancelRate(client, range: range)) ?? 0
        async let pending      = try? self.fetchPendingDeliveries(client)
        async let lowCount     = try? self.fetchLowStockCount(client)
        async let outstanding  = (try? self.fetchOutstanding(client)) ?? 0
        async let openQuotes   = (try? self.fetchOpenQuotes(client)) ?? 0

        async let series       = (try? self.fetchRevenueSeries(client, range: range)) ?? []
        async let topProducts  = (try? self.fetchTopProducts(client, range: range)) ?? []
        async let pipeline     = (try? self.fetchInvoicePipeline(client, range: range)) ?? []
        async let lowStockRows = (try? self.fetchLowStock(client)) ?? []
        async let recent       = (try? self.fetchRecentOrders(client)) ?? []

        let rev = StatDelta(current: revCurrent, previous: revPrevious)
        let ord = StatDelta(current: Double(ordCurrent), previous: Double(ordPrevious))

        let aov: StatDelta = {
            let cur = ordCurrent > 0 ? revCurrent / Double(ordCurrent) : 0
            let prev = ordPrevious > 0 ? revPrevious / Double(ordPrevious) : 0
            return StatDelta(current: cur, previous: prev)
        }()

        kpis = ShopKPIs(
            revenue: rev,
            orderCount: ord,
            averageOrderValue: aov,
            newCustomers: await newCustomers,
            cancelRate: await cancelRate,
            pendingDeliveries: await pending,
            lowStockCount: await lowCount,
            outstandingReceivable: await outstanding,
            openQuotes: await openQuotes
        )
        revenueSeries = await series
        self.topProducts = await topProducts
        invoicePipeline = await pipeline
        lowStock = await lowStockRows
        recentOrders = await recent
        lastRefresh = .now
        self.error = nil
    }

    private func safeDeltaInt(
        current: @Sendable () async throws -> Int,
        previous: @Sendable () async throws -> Int
    ) async -> StatDelta {
        async let cur = (try? current()) ?? 0
        async let prev = (try? previous()) ?? 0
        return await StatDelta(current: Double(cur), previous: Double(prev))
    }

    // MARK: - KPI fetchers

    private func periodDomain(_ range: DashboardPeriod.Range, field: String = "date_order") -> [JSON] {
        [
            .array([.string(field), .string(">="), .string(DateFormatter.odooDateTime.string(from: range.start))]),
            .array([.string(field), .string("<="), .string(DateFormatter.odooDateTime.string(from: range.end))])
        ]
    }

    private func fetchRevenue(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> Double {
        var domain: [JSON] = [
            .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])])
        ]
        domain.append(contentsOf: periodDomain(range))
        let rows = try await client.readGroup(
            model: "sale.order",
            domain: domain,
            fields: ["amount_total:sum"],
            groupBy: []
        )
        return rows.first?["amount_total"]?.doubleValue ?? 0
    }

    private func fetchOrderCount(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> Int {
        var domain: [JSON] = [
            .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])])
        ]
        domain.append(contentsOf: periodDomain(range))
        return try await client.callKw(model: "sale.order", method: "search_count", args: [.array(domain)])
    }

    private func fetchNewCustomers(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> Int {
        var domain: [JSON] = [
            .array([.string("customer_rank"), .string(">"), .int(0)])
        ]
        domain.append(contentsOf: periodDomain(range, field: "create_date"))
        return try await client.callKw(model: "res.partner", method: "search_count", args: [.array(domain)])
    }

    private func fetchCancelRate(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> Double {
        let periodDom = periodDomain(range)
        async let cancelled: Int = client.callKw(
            model: "sale.order",
            method: "search_count",
            args: [.array(periodDom + [.array([.string("state"), .string("="), .string("cancel")])])]
        )
        async let total: Int = client.callKw(
            model: "sale.order",
            method: "search_count",
            args: [.array(periodDom + [.array([.string("state"), .string("!="), .string("draft")])])]
        )
        let (c, t) = try await (cancelled, total)
        return t > 0 ? Double(c) / Double(t) : 0
    }

    private func fetchPendingDeliveries(_ client: OdooClient) async throws -> Int {
        try await client.callKw(
            model: "stock.picking",
            method: "search_count",
            args: [.array([
                .array([.string("state"), .string("in"), .array([.string("assigned"), .string("confirmed"), .string("waiting")])]),
                .array([.string("picking_type_id.code"), .string("="), .string("outgoing")])
            ])]
        )
    }

    /// KPI badge counter: number of orderpoints currently triggered
    /// (qty_to_order > 0). Falls back to 0 if no orderpoints exist —
    /// the LowStock card itself surfaces the fallback list.
    private func fetchLowStockCount(_ client: OdooClient) async throws -> Int {
        let count: Int = (try? await client.callKw(
            model: "stock.warehouse.orderpoint",
            method: "search_count",
            args: [.array([
                .array([.string("active"), .string("="), .bool(true)]),
                .array([.string("qty_to_order"), .string(">"), .int(0)])
            ])]
        )) ?? 0
        return count
    }

    private func fetchOutstanding(_ client: OdooClient) async throws -> Double {
        let rows = try await client.readGroup(
            model: "account.move",
            domain: [
                .array([.string("move_type"), .string("="), .string("out_invoice")]),
                .array([.string("state"), .string("="), .string("posted")]),
                .array([.string("payment_state"), .string("in"),
                        .array([.string("not_paid"), .string("partial"), .string("in_payment")])])
            ],
            fields: ["amount_residual:sum"],
            groupBy: []
        )
        return rows.first?["amount_residual"]?.doubleValue ?? 0
    }

    private func fetchOpenQuotes(_ client: OdooClient) async throws -> Int {
        try await client.callKw(
            model: "sale.order",
            method: "search_count",
            args: [.array([.array([.string("state"), .string("in"), .array([.string("draft"), .string("sent")])])])]
        )
    }

    // MARK: - Series + lists

    private func fetchRevenueSeries(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> [RevenuePoint] {
        var domain: [JSON] = [
            .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])])
        ]
        domain.append(contentsOf: periodDomain(range))
        let suffix = period.seriesInterval.odooSuffix
        let rows = try await client.readGroup(
            model: "sale.order",
            domain: domain,
            fields: ["amount_total:sum"],
            groupBy: ["date_order:\(suffix)"]
        )
        return rows.compactMap { row -> RevenuePoint? in
            guard let amount = row["amount_total"]?.doubleValue else { return nil }
            if let range = row["__range"]?.objectValue,
               let dateOrder = range["date_order"]?.objectValue,
               let from = dateOrder["from"]?.stringValue,
               let date = DateFormatter.odooDateTime.date(from: from) ?? DateFormatter.odooDate.date(from: from) {
                return RevenuePoint(bucketStart: date, total: amount)
            }
            return nil
        }
        .sorted { $0.bucketStart < $1.bucketStart }
    }

    /// Top products by *quantity sold* (not revenue) — what the merchant
    /// usually means when they ask "what's selling".
    private func fetchTopProducts(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> [TopProductRow] {
        var domain: [JSON] = [
            .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])]),
            .array([.string("product_id.type"), .string("!="), .string("service")])
        ]
        // sale.order.line inherits date via order_id
        for clause in periodDomain(range, field: "order_id.date_order") {
            domain.append(clause)
        }
        let rows = try await client.callKw(
            model: "sale.order.line",
            method: "read_group",
            kwargs: [
                "domain": .array(domain),
                "fields": .array([.string("price_subtotal:sum"), .string("product_uom_qty:sum")]),
                "groupby": .array([.string("product_id")]),
                "orderby": .string("product_uom_qty desc"),
                "limit": .int(5),
                "lazy": .bool(false)
            ],
            as: [[String: JSON]].self
        )
        return rows.compactMap { row -> TopProductRow? in
            guard
                let tuple = row["product_id"]?.arrayValue,
                tuple.count == 2,
                let id = tuple[0].intValue,
                let name = tuple[1].stringValue
            else { return nil }
            let revenue = row["price_subtotal"]?.doubleValue ?? 0
            let qty = row["product_uom_qty"]?.doubleValue ?? 0
            return TopProductRow(productId: id, name: name, quantity: qty, revenue: revenue)
        }
    }

    /// Pipeline view: confirmed sale.orders only, grouped by `invoice_status`.
    /// Skips raw `state` because Odoo writes a `draft` order for every
    /// website cart, which makes a state-based pie chart useless.
    private func fetchInvoicePipeline(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> [InvoicePipelineBucket] {
        var domain: [JSON] = [
            .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])])
        ]
        domain.append(contentsOf: periodDomain(range))
        let rows = try await client.callKw(
            model: "sale.order",
            method: "read_group",
            kwargs: [
                "domain": .array(domain),
                "fields": .array([.string("amount_total:sum")]),
                "groupby": .array([.string("invoice_status")]),
                "lazy": .bool(false)
            ],
            as: [[String: JSON]].self
        )
        return rows.compactMap { row -> InvoicePipelineBucket? in
            guard let status = row["invoice_status"]?.stringValue else { return nil }
            let count = row["__count"]?.intValue ?? row["invoice_status_count"]?.intValue ?? 0
            let total = row["amount_total"]?.doubleValue ?? 0
            return InvoicePipelineBucket(status: status, count: count, total: total)
        }
    }

    /// Reorder-aware low stock list.
    ///
    /// Strategy:
    /// 1. If the customer has configured `stock.warehouse.orderpoint`
    ///    rules, surface the products whose `virtual_available` falls
    ///    below their `product_min_qty`. These are the actionable rows
    ///    — the customer told us "reorder this when it gets low".
    /// 2. Otherwise fall back to storable, sellable products sorted by
    ///    forecast asc with a 5-unit floor — pragmatic but generic.
    private func fetchLowStock(_ client: OdooClient) async throws -> [LowStockRow] {
        let orderpoints: [OrderpointDTO] = (try? await client.searchRead(
            model: "stock.warehouse.orderpoint",
            domain: [.array([.string("active"), .string("="), .bool(true)])],
            fields: ["product_id", "product_min_qty"],
            limit: 200
        )) ?? []

        if !orderpoints.isEmpty {
            return try await fetchLowStockFromOrderpoints(client, orderpoints: orderpoints)
        }
        return try await fetchLowStockFallback(client)
    }

    private func fetchLowStockFromOrderpoints(
        _ client: OdooClient,
        orderpoints: [OrderpointDTO]
    ) async throws -> [LowStockRow] {
        let minByProduct: [Int: Double] = Dictionary(
            orderpoints.map { ($0.product_id.id, $0.product_min_qty) },
            uniquingKeysWith: max
        )
        let productIds = Array(minByProduct.keys)
        guard !productIds.isEmpty else { return [] }

        let products: [LowStockProductDTO] = try await client.searchRead(
            model: "product.product",
            domain: [.array([.string("id"), .string("in"), .array(productIds.map { .int($0) })])],
            fields: LowStockProductDTO.fields,
            limit: 500
        )
        return products.compactMap { p -> LowStockRow? in
            let minQty = minByProduct[p.id] ?? 0
            guard p.virtual_available < minQty else { return nil }
            return LowStockRow(
                productId: p.id,
                name: p.name,
                onHand: p.qty_available,
                forecast: p.virtual_available,
                minQty: minQty
            )
        }
        .sorted { ($0.forecast - ($0.minQty ?? 0)) < ($1.forecast - ($1.minQty ?? 0)) }
        .prefix(10)
        .map { $0 }
    }

    private func fetchLowStockFallback(_ client: OdooClient) async throws -> [LowStockRow] {
        // Keep the limit small and sort client-side: qty_available /
        // virtual_available are computed and not reliably orderable
        // server-side across Odoo versions.
        let products: [LowStockProductDTO] = try await client.searchRead(
            model: "product.product",
            domain: [
                .array([.string("type"), .string("="), .string("consu")]),
                .array([.string("is_storable"), .string("="), .bool(true)]),
                .array([.string("sale_ok"), .string("="), .bool(true)])
            ],
            fields: LowStockProductDTO.fields,
            limit: 500
        )
        return products
            .filter { $0.virtual_available <= 5 }
            .sorted { $0.virtual_available < $1.virtual_available }
            .prefix(10)
            .map {
                LowStockRow(
                    productId: $0.id,
                    name: $0.name,
                    onHand: $0.qty_available,
                    forecast: $0.virtual_available,
                    minQty: nil
                )
            }
    }

    private func fetchRecentOrders(_ client: OdooClient) async throws -> [SaleOrder] {
        try await client.searchRead(
            model: "sale.order",
            domain: [.array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])])],
            fields: SaleOrder.fields,
            limit: 5,
            order: "date_order desc"
        )
    }
}

private struct OrderpointDTO: Decodable, Sendable {
    let product_id: Many2One
    let product_min_qty: Double
}

private struct LowStockProductDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let qty_available: Double
    let virtual_available: Double

    static let fields: [String] = ["id", "name", "qty_available", "virtual_available"]
}
