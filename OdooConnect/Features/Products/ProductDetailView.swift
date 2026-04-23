import SwiftUI

struct ProductDetailView: View {
    @Environment(AuthManager.self) private var auth
    let productId: Int

    @State private var product: ProductDetail?
    @State private var sales30d: SalesSummary?
    @State private var variantAttributes: [ProductVariantAttribute] = []
    @State private var siblingVariantCount: Int = 0
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingEditor = false
    @State private var showingTransfer = false
    @State private var showingImageFullscreen = false

    var body: some View {
        ScrollView {
            if let product {
                VStack(alignment: .leading, spacing: 16) {
                    header(product)
                    if !variantAttributes.isEmpty {
                        variantCard(product)
                    }
                    stockCard(product)
                    salesCard
                }
                .padding()
            }
        }
        .navigationTitle(product?.display_name ?? "Produkt")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .overlay { if isLoading && product == nil { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if product != nil {
                    Menu {
                        Button("Bearbeiten", systemImage: "pencil") { showingEditor = true }
                        Button("Umlagern", systemImage: "arrow.left.arrow.right") { showingTransfer = true }
                    } label: {
                        Label("Aktionen", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let product {
                ProductEditSheet(product: product) {
                    await load()
                }
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showingTransfer) {
            if let product {
                NavigationStack {
                    StockTransferSheet(product: product) {
                        await load()
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showingImageFullscreen) {
            if let imageData, let uiImage = UIImage(data: imageData) {
                NavigationStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fertig") { showingImageFullscreen = false }
                            }
                        }
                }
            }
        }
        .errorAlert(error: $error)
    }

    private func header(_ product: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                productThumbnail
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.display_name).font(.title2.bold()).lineLimit(3)
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

    @ViewBuilder
    private var productThumbnail: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Button {
                showingImageFullscreen = true
            } label: {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.separator, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Produktbild vergrößern")
        } else {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
                .frame(width: 88, height: 88)
                .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .rect(cornerRadius: 14))
        }
    }

    private func variantCard(_ product: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Variante", systemImage: "square.grid.2x2.fill")
                    .font(.headline)
                Spacer()
                if siblingVariantCount > 1 {
                    Text("\(siblingVariantCount) Varianten gesamt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(variantAttributes) { attr in
                        HStack(spacing: 6) {
                            Text(attr.attribute_id.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(attr.name)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.12), in: Capsule())
                    }
                }
            }
            if let template = product.product_tmpl_id, !template.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Vorlage: \(template.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Fetch product (with image), sales summary in parallel.
            async let detailFetch: [ProductDetail] = client.searchRead(
                model: "product.product",
                domain: [.array([.string("id"), .string("="), .int(productId)])],
                fields: ProductDetail.fieldsWithImage,
                limit: 1
            )
            async let sales = fetchSales30d(client)

            let detail = try await detailFetch.first
            self.product = detail
            self.imageData = decodeImage(detail?.image_512)
            self.sales30d = try? await sales

            // Variant follow-up: only when this variant has attribute values.
            if let detail, !detail.product_template_attribute_value_ids.isEmpty {
                async let attributes = fetchVariantAttributes(client, ids: detail.product_template_attribute_value_ids)
                async let count = fetchSiblingVariantCount(client, templateId: detail.product_tmpl_id?.id ?? 0)
                variantAttributes = (try? await attributes) ?? []
                siblingVariantCount = (try? await count) ?? 0
            } else {
                variantAttributes = []
                siblingVariantCount = 0
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func decodeImage(_ base64: String?) -> Data? {
        guard let base64, !base64.isEmpty else { return nil }
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    private func fetchVariantAttributes(_ client: OdooClient, ids: [Int]) async throws -> [ProductVariantAttribute] {
        try await client.searchRead(
            model: "product.template.attribute.value",
            domain: [.array([.string("id"), .string("in"), .array(ids.map { .int($0) })])],
            fields: ProductVariantAttribute.fields,
            limit: ids.count
        )
    }

    private func fetchSiblingVariantCount(_ client: OdooClient, templateId: Int) async throws -> Int {
        guard templateId > 0 else { return 0 }
        let rows: [TemplateCountDTO] = try await client.searchRead(
            model: "product.template",
            domain: [.array([.string("id"), .string("="), .int(templateId)])],
            fields: ["product_variant_count"],
            limit: 1
        )
        return rows.first?.product_variant_count ?? 0
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
}

private struct TemplateCountDTO: Decodable, Sendable {
    let product_variant_count: Int
}

struct SalesSummary: Sendable, Equatable {
    let quantity: Double
    let revenue: Double
}
