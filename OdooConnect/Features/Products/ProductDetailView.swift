import SwiftUI

struct ProductDetailView: View {
    @Environment(AuthManager.self) private var auth
    let productId: Int

    @State private var product: ProductDetail?
    @State private var sales30d: SalesSummary?
    @State private var isLoading = false
    @State private var error: String?
    @State private var editing = false
    @State private var draftPrice: Double = 0
    @State private var draftSaleOk: Bool = true

    var body: some View {
        ScrollView {
            if let product {
                VStack(alignment: .leading, spacing: 16) {
                    header(product)
                    stockCard(product)
                    salesCard
                    if editing {
                        editCard(product)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(product?.name ?? "Produkt")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .overlay { if isLoading && product == nil { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let product {
                    Button(editing ? "Fertig" : "Bearbeiten") {
                        if editing {
                            Task { await save(product) }
                        } else {
                            draftPrice = product.list_price
                            draftSaleOk = product.sale_ok
                            editing = true
                        }
                    }
                }
            }
        }
        .alert("Fehler", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func header(_ product: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                    .frame(width: 72, height: 72)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name).font(.title2.bold())
                    if let code = product.default_code {
                        Text(code).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    }
                    if let barcode = product.barcode {
                        Label(barcode, systemImage: "barcode").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let desc = product.description_sale, !desc.isEmpty {
                Text(desc).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text(product.list_price, format: .currency(code: auth.companyCurrency.code))
                    .font(.title.bold().monospacedDigit())
                Spacer()
                StockBadge(product: product)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func stockCard(_ product: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Lagerbestand", systemImage: "archivebox").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                stat("Verfügbar",   value: product.qty_available,   tint: product.qty_available <= 0 ? .red : .green, symbol: "cube.box.fill")
                stat("Prognose",    value: product.virtual_available, tint: .blue,   symbol: "chart.line.uptrend.xyaxis")
                stat("Eingehend",   value: product.incoming_qty,      tint: .teal,   symbol: "arrow.down.to.line")
                stat("Ausgehend",   value: product.outgoing_qty,      tint: .orange, symbol: "arrow.up.from.line")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private func stat(_ title: String, value: Double, tint: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(value, specifier: "%.0f")")
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText(value: value))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private var salesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Verkäufe 30 Tage", systemImage: "chart.bar.fill").font(.headline)
            if let sales30d {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Menge").font(.caption).foregroundStyle(.secondary)
                        Text("\(sales30d.quantity, specifier: "%.0f") \(product?.uomSymbol ?? "")")
                            .font(.title3.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Umsatz").font(.caption).foregroundStyle(.secondary)
                        Text(sales30d.revenue, format: .currency(code: auth.companyCurrency.code))
                            .font(.title3.bold().monospacedDigit())
                    }
                }
            } else {
                HStack { ProgressView(); Text("Lade...").foregroundStyle(.secondary) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func editCard(_ product: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Bearbeiten", systemImage: "pencil").font(.headline)
            HStack {
                Text("Listenpreis")
                Spacer()
                TextField("", value: $draftPrice, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 120)
            }
            Toggle("Verkaufbar", isOn: $draftSaleOk)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let detail: [ProductDetail] = client.searchRead(
                model: "product.product",
                domain: [.array([.string("id"), .string("="), .int(productId)])],
                fields: ProductDetail.fields,
                limit: 1
            )
            async let sales = fetchSales30d(client)
            let detailArray = try await detail
            self.product = detailArray.first
            self.sales30d = try? await sales
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fetchSales30d(_ client: OdooClient) async throws -> SalesSummary {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let sinceString = DateFormatter.odooDateTime.string(from: since)
        let rows: [[String: JSON]] = try await client.callKw(
            model: "sale.order.line",
            method: "read_group",
            kwargs: [
                "domain": .array([
                    .array([.string("product_id"), .string("="), .int(productId)]),
                    .array([.string("order_id.state"), .string("in"),
                            .array([.string("sale"), .string("done")])]),
                    .array([.string("order_id.date_order"), .string(">="), .string(sinceString)])
                ]),
                "fields": .array([.string("product_uom_qty:sum"), .string("price_subtotal:sum")]),
                "groupby": .array([]),
                "lazy": .bool(false)
            ],
            as: [[String: JSON]].self
        )
        let row = rows.first
        return SalesSummary(
            quantity: row?["product_uom_qty"]?.doubleValue ?? 0,
            revenue: row?["price_subtotal"]?.doubleValue ?? 0
        )
    }

    private func save(_ product: ProductDetail) async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await client.write(
                model: "product.product",
                ids: [product.id],
                values: [
                    "list_price": .double(draftPrice),
                    "sale_ok": .bool(draftSaleOk)
                ]
            )
            editing = false
            await load()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct SalesSummary: Sendable, Equatable {
    let quantity: Double
    let revenue: Double
}
