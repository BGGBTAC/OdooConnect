import Foundation
import Observation

@Observable
@MainActor
final class DashboardViewModel {
    var period: DashboardPeriod = .last30 {
        didSet { if oldValue != period { Task { await loadPeriod() } } }
    }

    // Aggregate KPIs (all in one struct so the view animates coherently).
    var kpis: ShopKPIs = ShopKPIs()

    // Series & lists
    var revenueSeries: [RevenuePoint] = []
    var topProducts: [TopProductRow] = []
    var orderBuckets: [OrderStateBucket] = []
    var lowStock: [LowStockRow] = []
    var recentOrders: [SaleOrder] = []

    var isLoading: Bool = false
    var lastRefresh: Date?
    var error: String?

    private var client: OdooClient?

    func load(using client: OdooClient?) async {
        self.client = client
        await loadPeriod()
    }

    private func loadPeriod() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }

        let range = period.range()
        let previous = period.previousRange()

        async let revenue      = safeDelta { try await self.fetchRevenue(client, range: range) } previous: { try await self.fetchRevenue(client, range: previous) }
        async let orders       = safeDeltaInt { try await self.fetchOrderCount(client, range: range) } previous: { try await self.fetchOrderCount(client, range: previous) }
        async let newCustomers = safeDeltaInt { try await self.fetchNewCustomers(client, range: range) } previous: { try await self.fetchNewCustomers(client, range: previous) }
        async let cancelRate   = (try? self.fetchCancelRate(client, range: range)) ?? 0
        async let pending      = try? self.fetchPendingDeliveries(client)
        async let lowCount     = try? self.fetchLowStockCount(client)
        async let outstanding  = (try? self.fetchOutstanding(client)) ?? 0
        async let openQuotes   = (try? self.fetchOpenQuotes(client)) ?? 0

        async let series       = (try? self.fetchRevenueSeries(client, range: range)) ?? []
        async let topProducts  = (try? self.fetchTopProducts(client, range: range)) ?? []
        async let buckets      = (try? self.fetchOrderBuckets(client, range: range)) ?? []
        async let lowStockRows = (try? self.fetchLowStock(client)) ?? []
        async let recent       = (try? self.fetchRecentOrders(client)) ?? []

        let rev = await revenue
        let ord = await orders

        let aov: StatDelta = {
            let cur = ord.current > 0 ? rev.current / ord.current : 0
            let prev = ord.previous > 0 ? rev.previous / ord.previous : 0
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
        orderBuckets = await buckets
        lowStock = await lowStockRows
        recentOrders = await recent
        lastRefresh = .now
    }

    private func safeDelta(
        current: () async throws -> Double,
        previous: () async throws -> Double
    ) async -> StatDelta {
        async let cur = (try? current()) ?? 0
        async let prev = (try? previous()) ?? 0
        return await StatDelta(current: cur, previous: prev)
    }

    private func safeDeltaInt(
        current: () async throws -> Int,
        previous: () async throws -> Int
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

    private func fetchLowStockCount(_ client: OdooClient) async throws -> Int {
        try await client.callKw(
            model: "stock.quant",
            method: "search_count",
            args: [.array([
                .array([.string("location_id.usage"), .string("="), .string("internal")]),
                .array([.string("quantity"), .string("<="), .int(5)])
            ])]
        )
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

    private func fetchTopProducts(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> [TopProductRow] {
        var domain: [JSON] = [
            .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])])
        ]
        // sale.order.line doesn't have date_order itself but inherits via order_id
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
                "orderby": .string("price_subtotal desc"),
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

    private func fetchOrderBuckets(_ client: OdooClient, range: DashboardPeriod.Range) async throws -> [OrderStateBucket] {
        let rows = try await client.callKw(
            model: "sale.order",
            method: "read_group",
            kwargs: [
                "domain": .array(periodDomain(range)),
                "fields": .array([.string("amount_total:sum")]),
                "groupby": .array([.string("state")]),
                "lazy": .bool(false)
            ],
            as: [[String: JSON]].self
        )
        return rows.compactMap { row -> OrderStateBucket? in
            guard let state = row["state"]?.stringValue else { return nil }
            let count = row["__count"]?.intValue ?? row["state_count"]?.intValue ?? 0
            let total = row["amount_total"]?.doubleValue ?? 0
            return OrderStateBucket(state: state, count: count, total: total)
        }
    }

    private func fetchLowStock(_ client: OdooClient) async throws -> [LowStockRow] {
        let rows = try await client.callKw(
            model: "stock.quant",
            method: "read_group",
            kwargs: [
                "domain": .array([
                    .array([.string("location_id.usage"), .string("="), .string("internal")])
                ]),
                "fields": .array([.string("quantity:sum")]),
                "groupby": .array([.string("product_id")]),
                "orderby": .string("quantity asc"),
                "limit": .int(10),
                "lazy": .bool(false)
            ],
            as: [[String: JSON]].self
        )
        return rows.compactMap { row -> LowStockRow? in
            guard
                let tuple = row["product_id"]?.arrayValue,
                tuple.count == 2,
                let id = tuple[0].intValue,
                let name = tuple[1].stringValue
            else { return nil }
            let qty = row["quantity"]?.doubleValue ?? 0
            guard qty <= 5 else { return nil } // threshold
            return LowStockRow(productId: id, name: name, quantity: qty)
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
