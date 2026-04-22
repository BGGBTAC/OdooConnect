import Foundation
import Observation

struct RevenuePoint: Identifiable, Sendable {
    let weekStart: Date
    let total: Double
    var id: Date { weekStart }
}

@Observable
@MainActor
final class DashboardViewModel {
    var monthlyRevenue: Double = 0
    var openQuotes: Int = 0
    var openOrders: Int = 0
    var outstandingReceivable: Double = 0
    var weeklyRevenue: [RevenuePoint] = []
    var isLoading: Bool = false
    var error: String?

    func load(using client: OdooClient?) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let monthly = fetchMonthlyRevenue(client)
            async let quotes = fetchOpenCount(client, model: "sale.order", domain: [
                .array([.string("state"), .string("in"), .array([.string("draft"), .string("sent")])])
            ])
            async let orders = fetchOpenCount(client, model: "sale.order", domain: [
                .array([.string("state"), .string("="), .string("sale")])
            ])
            async let receivable = fetchOutstanding(client)
            async let weekly = fetchWeeklyRevenue(client)

            self.monthlyRevenue = try await monthly
            self.openQuotes = try await quotes
            self.openOrders = try await orders
            self.outstandingReceivable = try await receivable
            self.weeklyRevenue = try await weekly
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fetchOpenCount(_ client: OdooClient, model: String, domain: [JSON]) async throws -> Int {
        try await client.callKw(
            model: model,
            method: "search_count",
            args: [.array(domain)]
        )
    }

    /// Server-side aggregate: pulls a single grouped row instead of every order.
    private func fetchMonthlyRevenue(_ client: OdooClient) async throws -> Double {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        let startString = DateFormatter.odooDate.string(from: start)
        let rows = try await client.readGroup(
            model: "sale.order",
            domain: [
                .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])]),
                .array([.string("date_order"), .string(">="), .string(startString)])
            ],
            fields: ["amount_total"],
            groupBy: []
        )
        return rows.first?["amount_total"]?.doubleValue ?? 0
    }

    /// Server-side aggregate: avoids paging every open invoice client-side.
    private func fetchOutstanding(_ client: OdooClient) async throws -> Double {
        let rows = try await client.readGroup(
            model: "account.move",
            domain: [
                .array([.string("move_type"), .string("="), .string("out_invoice")]),
                .array([.string("state"), .string("="), .string("posted")]),
                .array([.string("payment_state"), .string("in"), .array([.string("not_paid"), .string("partial"), .string("in_payment")])])
            ],
            fields: ["amount_residual"],
            groupBy: []
        )
        return rows.first?["amount_residual"]?.doubleValue ?? 0
    }

    /// 8-week chart still client-buckets — Odoo's date:week label format is
    /// version-dependent and the dataset is small enough that the saving
    /// would be marginal.
    private func fetchWeeklyRevenue(_ client: OdooClient) async throws -> [RevenuePoint] {
        let cal = Calendar(identifier: .iso8601)
        let startOfThisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        guard let start = cal.date(byAdding: .weekOfYear, value: -7, to: startOfThisWeek) else { return [] }
        let startString = DateFormatter.odooDate.string(from: start)

        let orders: [WeeklyOrderDTO] = try await client.searchRead(
            model: "sale.order",
            domain: [
                .array([.string("state"), .string("in"), .array([.string("sale"), .string("done")])]),
                .array([.string("date_order"), .string(">="), .string(startString)])
            ],
            fields: ["amount_total", "date_order"],
            order: "date_order asc"
        )

        var bucket: [Date: Double] = [:]
        for order in orders {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: order.date_order)
            guard let weekStart = cal.date(from: comps) else { continue }
            bucket[weekStart, default: 0] += order.amount_total
        }
        return bucket
            .map { RevenuePoint(weekStart: $0.key, total: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
    }
}

private struct WeeklyOrderDTO: Decodable, Sendable {
    let amount_total: Double
    let date_order: Date
}
