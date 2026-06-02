import Foundation
import Observation

@Observable
@MainActor
final class DashboardViewModel {
    // Period-driven reloads are owned by the view's `.task(id: model.period)`,
    // which funnels through `load(using:companyCurrencyId:)` and the single
    // in-flight guard below — so `period` no longer triggers a load in didSet.
    var period: DashboardPeriod = .mtd

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
    private var companyCurrencyId: Int = 0
    /// Session cache of res.currency rates (foreign units per 1 company unit).
    /// Only fetched lazily when a foreign-currency bucket actually appears.
    private var rateCache: [Int: Double]?

    /// The single in-flight load. Cancel-and-replace ⇒ latest request wins,
    /// so overlapping triggers (.task / scenePhase / pull-to-refresh /
    /// tab-return) collapse to ONE RPC fan instead of stacking 2–3.
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    /// Single public entry point for every trigger. Awaitable end-to-end so
    /// `.refreshable` keeps spinning until the work actually completes.
    func load(using client: OdooClient?, companyCurrencyId: Int) async {
        // Don't clobber a previously valid client with nil — when the
        // Dashboard is rebuilt before AuthManager has fully restored,
        // `auth.client` can be nil for a tick. Keep what we have.
        if let client { self.client = client }
        if companyCurrencyId > 0 { self.companyCurrencyId = companyCurrencyId }

        let period = self.period
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadPeriod(for: period)
        }
        loadTask = task
        await task.value
        // Only the latest load clears the spinner; a superseded one must not.
        if generation == loadGeneration { isLoading = false }
    }

    private func loadPeriod(for period: DashboardPeriod) async {
        guard let client else { return }

        let range = period.range()
        let previous = period.previousRange()
        if Task.isCancelled { return }

        // Primary KPIs: revenue + order count drive everything else and
        // their failure usually indicates a real problem (network down,
        // session expired). If they throw, keep the previously-rendered
        // numbers and surface the error — wiping to zero leaves the user
        // staring at a blank dashboard with no clue why.
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
            // Superseded by a newer load (period change / pull-to-refresh).
            return
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        // Secondary fetches are individually resilient: a failure in any one
        // shouldn't blank the whole board. They run in parallel with sensible
        // empty defaults.
        async let newCustomers = safeDeltaInt { try await self.fetchNewCustomers(client, range: range) } previous: { try await self.fetchNewCustomers(client, range: previous) }
        async let cancelRate   = (try? self.fetchCancelRate(client, range: range)) ?? 0
        async let pending      = try? self.fetchPendingDeliveries(client)
        async let lowCount     = try? self.fetchLowStockCount(client)
        async let outstanding  = (try? self.fetchOutstanding(client)) ?? 0
        async let openQuotes   = (try? self.fetchOpenQuotes(client)) ?? 0

        async let series       = (try? self.fetchRevenueSeries(client, range: range, period: period)) ?? []
        async let topProductsResult = (try? self.fetchTopProducts(client, range: range)) ?? []
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

        let newKpis = ShopKPIs(
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
        let newSeries = await series
        let newTop = await topProductsResult
        let newPipeline = await pipeline
        let newLow = await lowStockRows
        let newRecent = await recent

        // Don't commit stale data if a newer load superseded us mid-flight.
        if Task.isCancelled { return }

        kpis = newKpis
        revenueSeries = newSeries
        topProducts = newTop
        invoicePipeline = newPipeline
        lowStock = newLow
        recentOrders = newRecent
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

    // MARK: - Multi-currency helpers

    private func currencyId(from row: [String: JSON]) -> Int? {
        guard let tuple = row["currency_id"]?.arrayValue, tuple.count == 2 else { return nil }
        return tuple[0].intValue
    }

    /// Builds a converter for the given read_group rows. When every row is
    /// already in the company currency (the common single-currency case) it
    /// returns an empty converter and performs NO extra RPC. Otherwise it
    /// fetches (and caches) res.currency rates once.
    private func converter(for rows: [[String: JSON]], using client: OdooClient) async -> CurrencyConverter {
        let hasForeign = rows.contains { row in
            guard let cur = currencyId(from: row) else { return false }
            return cur != companyCurrencyId
        }
        guard hasForeign else {
            return CurrencyConverter(rates: [:], companyCurrencyId: companyCurrencyId)
        }
        if let rateCache {
            return CurrencyConverter(rates: rateCache, companyCurrencyId: companyCurrencyId)
        }
        let dtos: [CurrencyRateDTO] = (try? await client.searchRead(
            model: "res.currency",
            domain: [.array([.string("active"), .string("="), .bool(true)])],
            fields: CurrencyRateDTO.fields,
            limit: 500
        )) ?? []
        let map = Dictionary(dtos.map { ($0.id, $0.rate) }, uniquingKeysWith: { a, _ in a })
        rateCache = map
        return CurrencyConverter(rates: map, companyCurrencyId: companyCurrencyId)
    }

    /// Sums one monetary field across read_group rows, converting each row's
    /// amount from its `currency_id` into company currency.
    private func sumInCompany(_ rows: [[String: JSON]], field: String, using client: OdooClient) async -> Double {
        let conv = await converter(for: rows, using: client)
        return rows.reduce(0.0) { acc, row in
            let raw = row[field]?.doubleValue ?? 0
            guard let cur = currencyId(from: row) else { return acc + raw }
            return acc + conv.toCompany(raw, currencyId: cur)
        }
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
        // Group by currency_id so multi-currency orders are converted to the
        // company currency instead of being summed as if same-unit.
        let rows = try await client.readGroup(
            model: "sale.order",
            domain: domain,
            fields: ["amount_total:sum"],
            groupBy: ["currency_id"]
        )
        return await sumInCompany(rows, field: "amount_total", using: client)
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
        // amount_residual_signed is stored in the COMPANY currency (signed),
        // so no per-currency grouping/conversion is needed — exact and one RPC.
        let rows = try await client.readGroup(
            model: "account.move",
            domain: [
                .array([.string("move_type"), .string("="), .string("out_invoice")]),
                .array([.string("state"), .string("="), .string("posted")]),
                .array([.string("payment_state"), .string("in"),
                        .array([.string("not_paid"), .string("partial"), .string("in_payment")])])
            ],
            fields: ["amount_residual_signed:sum"],
            groupBy: []
        )
        return rows.first?["amount_residual_signed"]?.doubleValue ?? 0
    }

    private func fetchOpenQuotes(_ client: OdooClient) async throws -> Int {
        try await client.callKw(
            model: "sale.order",
            method: "search_count",
            args: [.array([.array([.string("state"), .string("in"), .array([.string("draft"), .string("sent")])])])]
        )
    }

    // MARK: - Series + lists

    private func fetchRevenueSeries(_ client: OdooClient, range: DashboardPeriod.Range, period: DashboardPeriod) async throws -> [RevenuePoint] {
        var domain: [JSON] = [
            .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])])
        ]
        domain.append(contentsOf: periodDomain(range))
        let suffix = period.seriesInterval.odooSuffix
        let rows = try await client.readGroup(
            model: "sale.order",
            domain: domain,
            fields: ["amount_total:sum"],
            groupBy: ["date_order:\(suffix)", "currency_id"]
        )
        let conv = await converter(for: rows, using: client)
        var byBucket: [Date: Double] = [:]
        for row in rows {
            guard let amount = row["amount_total"]?.doubleValue else { continue }
            guard
                let r = row["__range"]?.objectValue,
                let dateOrder = r["date_order"]?.objectValue,
                let from = dateOrder["from"]?.stringValue,
                let date = DateFormatter.odooDateTime.date(from: from) ?? DateFormatter.odooDate.date(from: from)
            else { continue }
            let converted = currencyId(from: row).map { conv.toCompany(amount, currencyId: $0) } ?? amount
            byBucket[date, default: 0] += converted
        }
        return byBucket
            .map { RevenuePoint(bucketStart: $0.key, total: $0.value) }
            .sorted { $0.bucketStart < $1.bucketStart }
    }

    /// Top products by *quantity sold* (not revenue) — what the merchant
    /// usually means when they ask "what's selling". Revenue is converted to
    /// company currency; grouping adds currency_id so a server `limit` would
    /// no longer mean "top 5 products", hence the client-side collapse + rank.
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
                "groupby": .array([.string("product_id"), .string("currency_id")]),
                "lazy": .bool(false)
            ],
            as: [[String: JSON]].self
        )
        let conv = await converter(for: rows, using: client)
        var byProduct: [Int: (name: String, qty: Double, revenue: Double)] = [:]
        for row in rows {
            guard
                let tuple = row["product_id"]?.arrayValue,
                tuple.count == 2,
                let id = tuple[0].intValue,
                let name = tuple[1].stringValue
            else { continue }
            let qty = row["product_uom_qty"]?.doubleValue ?? 0
            let rawRevenue = row["price_subtotal"]?.doubleValue ?? 0
            let revenue = currencyId(from: row).map { conv.toCompany(rawRevenue, currencyId: $0) } ?? rawRevenue
            let prev = byProduct[id] ?? (name, 0, 0)
            byProduct[id] = (name, prev.qty + qty, prev.revenue + revenue)
        }
        return byProduct
            .map { TopProductRow(productId: $0.key, name: $0.value.name, quantity: $0.value.qty, revenue: $0.value.revenue) }
            .sorted { $0.quantity > $1.quantity }
            .prefix(5)
            .map { $0 }
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
                "groupby": .array([.string("invoice_status"), .string("currency_id")]),
                "lazy": .bool(false)
            ],
            as: [[String: JSON]].self
        )
        let conv = await converter(for: rows, using: client)
        var byStatus: [String: (count: Int, total: Double)] = [:]
        for row in rows {
            guard let status = row["invoice_status"]?.stringValue else { continue }
            let count = row["__count"]?.intValue ?? row["invoice_status_count"]?.intValue ?? 0
            let rawTotal = row["amount_total"]?.doubleValue ?? 0
            let total = currencyId(from: row).map { conv.toCompany(rawTotal, currencyId: $0) } ?? rawTotal
            let prev = byStatus[status] ?? (0, 0)
            byStatus[status] = (prev.count + count, prev.total + total)
        }
        return byStatus.map { InvoicePipelineBucket(status: $0.key, count: $0.value.count, total: $0.value.total) }
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

private struct CurrencyRateDTO: Decodable, Sendable {
    let id: Int
    let rate: Double
    static let fields: [String] = ["id", "rate"]
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
