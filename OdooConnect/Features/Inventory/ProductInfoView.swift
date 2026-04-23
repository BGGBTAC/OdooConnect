import SwiftUI

/// Scan a barcode → look up product → render the operationally most
/// useful info on one screen: image, variant, last sale, stock per
/// location, with a one-tap shortcut into the existing inventory
/// adjustment sheet.
struct ProductInfoView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var scannedCode: String?
    @State private var product: ProductDetail?
    @State private var variantAttributes: [ProductVariantAttribute] = []
    @State private var stockByLocation: [LocationStockRow] = []
    @State private var lastSale: LastSaleInfo?
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var error: String?
    @State private var notFoundCode: String?
    @State private var adjusting: ProductDetail?

    var body: some View {
        ZStack(alignment: .top) {
            BarcodeScannerView(
                mode: .continuous(debounce: .milliseconds(2000)),
                onScan: { code in
                    Task { await lookup(code: code) }
                },
                onError: { error = $0 }
            )
            .ignoresSafeArea(edges: .horizontal)

            if let product {
                productCard(product)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let code = notFoundCode {
                notFoundCard(code: code)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                    .transition(.opacity)
            } else if isLoading {
                loadingPill
                    .padding(.top, Spacing.sm)
            } else {
                hintPill
                    .padding(.top, Spacing.sm)
            }
        }
        .navigationTitle("Produkt-Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }
            }
            if product != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        product = nil
                        scannedCode = nil
                        notFoundCode = nil
                    } label: {
                        Label("Neuer Scan", systemImage: "barcode.viewfinder")
                    }
                }
            }
        }
        .sheet(item: $adjusting) { p in
            NavigationStack {
                InventoryAdjustmentSheet(product: p) {
                    adjusting = nil
                    if let code = scannedCode {
                        await lookup(code: code, force: true)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .errorAlert(error: $error)
    }

    // MARK: - Cards

    private var hintPill: some View {
        Label("Barcode auf Artikel scannen", systemImage: "barcode.viewfinder")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(.black.opacity(0.55), in: .capsule)
            .foregroundStyle(.white)
    }

    private var loadingPill: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white).controlSize(.small)
            Text("Lade…").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.black.opacity(0.55), in: .capsule)
    }

    private func notFoundCard(code: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Kein Produkt gefunden", systemImage: "questionmark.circle.fill")
                .font(.headline).foregroundStyle(Theme.danger)
            Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text("Stelle sicher, dass der Barcode in Odoo bei einem product.product hinterlegt ist.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .cardSurface(.standard)
    }

    private func productCard(_ product: ProductDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header(product)
                if !variantAttributes.isEmpty {
                    variantSection
                }
                stockSection
                if let lastSale {
                    lastSaleSection(lastSale)
                }
                adjustButton(product)
            }
            .padding(.bottom, Spacing.lg)
        }
        .frame(maxHeight: 520)
        .cardSurface(.standard)
    }

    private func header(_ product: ProductDetail) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(product.display_name)
                    .font(.title3.weight(.bold))
                    .lineLimit(3)
                if let code = product.default_code {
                    Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if let barcode = product.barcode {
                    Label(barcode, systemImage: "barcode")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(product.list_price, format: .currency(code: auth.companyCurrency.code))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(Theme.brand)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let imageData, let img = UIImage(data: imageData) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 76)
                .clipShape(.rect(cornerRadius: 12))
        } else {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.brand)
                .frame(width: 76, height: 76)
                .background(Theme.brand.opacity(0.12), in: .rect(cornerRadius: 12))
        }
    }

    private var variantSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Variante")
                .font(.caption.weight(.bold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(variantAttributes) { attr in
                        Text(attr.displayLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.brand.opacity(0.12), in: .capsule)
                    }
                }
            }
        }
    }

    private var stockSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Lagerbestand")
                    .font(.caption.weight(.bold))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                if let p = product {
                    Text("Total: \(formatted(p.qty_available))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if stockByLocation.isEmpty {
                Text("Kein Bestand an internen Standorten.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(stockByLocation) { row in
                    HStack {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(Theme.slate)
                            .font(.caption)
                        Text(row.locationName)
                            .font(.subheadline)
                        Spacer()
                        Text(formatted(row.quantity))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(row.quantity <= 0 ? Theme.danger
                                            : row.quantity <= 5 ? Theme.warning
                                            : Theme.success)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func lastSaleSection(_ sale: LastSaleInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zuletzt verkauft")
                .font(.caption.weight(.bold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "calendar").foregroundStyle(Theme.brand).font(.caption)
                Text(sale.date, style: .date).font(.subheadline)
                Spacer()
                Text("\(formatted(sale.quantity)) \(product?.uomSymbol ?? "")")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func adjustButton(_ product: ProductDetail) -> some View {
        Button {
            adjusting = product
        } label: {
            HStack {
                Image(systemName: "slider.horizontal.below.square.filled.and.square")
                Text("Bestand korrigieren").fontWeight(.semibold)
                Spacer()
                Image(systemName: "arrow.right").opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Theme.brand, in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Data

    private func lookup(code: String, force: Bool = false) async {
        guard let client = auth.client else { return }
        if !force, code == scannedCode, product != nil { return }
        scannedCode = code
        notFoundCode = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let products: [ProductDetail] = try await client.searchRead(
                model: "product.product",
                domain: [.array([.string("barcode"), .string("="), .string(code)])],
                fields: ProductDetail.fieldsWithImage,
                limit: 1
            )
            guard let p = products.first else {
                product = nil
                imageData = nil
                stockByLocation = []
                lastSale = nil
                variantAttributes = []
                notFoundCode = code
                return
            }
            withAnimation(.smooth) { product = p }
            imageData = p.image_512.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }

            // Load auxiliary info in parallel.
            async let stocks = fetchStockByLocation(client, productId: p.id)
            async let attrs = fetchAttributes(client, ids: p.product_template_attribute_value_ids)
            async let sale = fetchLastSale(client, productId: p.id)

            stockByLocation = (try? await stocks) ?? []
            variantAttributes = (try? await attrs) ?? []
            lastSale = (try? await sale)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fetchStockByLocation(_ client: OdooClient, productId: Int) async throws -> [LocationStockRow] {
        let rows: [QuantWithLocationDTO] = try await client.searchRead(
            model: "stock.quant",
            domain: [
                .array([.string("product_id"), .string("="), .int(productId)]),
                .array([.string("location_id.usage"), .string("="), .string("internal")])
            ],
            fields: QuantWithLocationDTO.fields,
            limit: 200,
            order: "location_id asc"
        )
        // Group by location (multiple quants per location possible if lots).
        var byLocation: [Int: LocationStockRow] = [:]
        for row in rows {
            let key = row.location_id.id
            if var existing = byLocation[key] {
                existing.quantity += row.quantity
                byLocation[key] = existing
            } else {
                byLocation[key] = LocationStockRow(
                    locationId: key,
                    locationName: row.location_id.name,
                    quantity: row.quantity
                )
            }
        }
        return byLocation.values.sorted { $0.locationName < $1.locationName }
    }

    private func fetchAttributes(_ client: OdooClient, ids: [Int]) async throws -> [ProductVariantAttribute] {
        guard !ids.isEmpty else { return [] }
        return try await client.searchRead(
            model: "product.template.attribute.value",
            domain: [.array([.string("id"), .string("in"), .array(ids.map { .int($0) })])],
            fields: ProductVariantAttribute.fields,
            limit: ids.count
        )
    }

    private func fetchLastSale(_ client: OdooClient, productId: Int) async throws -> LastSaleInfo? {
        let lines: [LastSaleDTO] = try await client.searchRead(
            model: "sale.order.line",
            domain: [
                .array([.string("product_id"), .string("="), .int(productId)]),
                .array([.string("order_id.state"), .string("in"),
                        .array([.string("sale"), .string("done")])])
            ],
            fields: LastSaleDTO.fields,
            limit: 1,
            order: "order_id desc"
        )
        guard let row = lines.first else { return nil }
        return LastSaleInfo(date: row.create_date, quantity: row.product_uom_qty)
    }

    private func formatted(_ value: Double) -> String { value.qtyFormatted }
}

private struct LocationStockRow: Identifiable, Sendable, Equatable {
    let locationId: Int
    let locationName: String
    var quantity: Double
    var id: Int { locationId }
}

private struct LastSaleInfo: Sendable, Equatable {
    let date: Date
    let quantity: Double
}

// MARK: - DTOs

private struct QuantWithLocationDTO: Decodable, Sendable {
    let id: Int
    let location_id: Many2One
    let quantity: Double

    static let fields: [String] = ["id", "location_id", "quantity"]
}

private struct LastSaleDTO: Decodable, Sendable {
    let id: Int
    let product_uom_qty: Double
    let create_date: Date

    static let fields: [String] = ["id", "product_uom_qty", "create_date"]
}
