import SwiftUI

struct InventoryView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @State private var showingScanner = false
    @State private var showingProductInfo = false
    @State private var lowStock: [StockQuant] = []
    @State private var searchText = ""
    @State private var searchResults: [ProductDetail] = []
    @State private var isLoading = false
    @State private var scanError: String?
    @State private var adjustingProduct: ProductDetail?
    @State private var lookupError: String?

    var body: some View {
        List {
            Section {
                Button {
                    showingProductInfo = true
                } label: {
                    HStack {
                        Image(systemName: "barcode.viewfinder").font(.title2)
                            .foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Produkt-Info scannen").font(.headline)
                            Text("Bestand pro Lager, letzter Verkauf, Korrektur")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Button {
                    showingScanner = true
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.below.square.filled.and.square").font(.title2)
                            .foregroundStyle(Theme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bestand korrigieren").font(.headline)
                            Text("Schneller Scan, sofort anpassen")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if !searchText.isEmpty {
                Section("Suchergebnisse") {
                    ForEach(searchResults) { product in
                        Button {
                            adjustingProduct = product
                        } label: {
                            ProductRow(product: product, currencyCode: auth.companyCurrency.code)
                        }
                        .buttonStyle(.plain)
                    }
                    if searchResults.isEmpty && !isLoading {
                        Text("Keine Treffer").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Kritischer Bestand") {
                    if lowStock.isEmpty && !isLoading {
                        ContentUnavailableView("Alles auf Lager", systemImage: "checkmark.seal")
                    } else {
                        ForEach(lowStock) { quant in
                            Button {
                                Task { await loadProduct(id: quant.product_id.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(quant.product_id.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(quant.location_id.name).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(quant.quantity, specifier: "%.0f")")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(quant.quantity <= 0 ? .red : .orange)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Inventur")
        .searchable(text: $searchText, prompt: "Name, Artikelnr. oder Barcode")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
        .task { await loadLowStock() }
        .refreshable { await loadLowStock() }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                ZStack {
                    BarcodeScannerView(
                        onScan: { code in
                            showingScanner = false
                            Task { await handleScan(code) }
                        },
                        onError: { message in
                            scanError = message
                            showingScanner = false
                        }
                    )
                    VStack {
                        Spacer()
                        Text("Code im grünen Rahmen ausrichten")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { showingScanner = false }
                    }
                }
            }
        }
        .sheet(item: $adjustingProduct) { product in
            NavigationStack {
                InventoryAdjustmentSheet(product: product) {
                    adjustingProduct = nil
                    await loadLowStock()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showingProductInfo) {
            NavigationStack {
                ProductInfoView()
            }
        }
        .alert("Scanner", isPresented: .constant(scanError != nil)) {
            Button("OK") { scanError = nil }
        } message: { Text(scanError ?? "") }
        .alert("Nicht gefunden", isPresented: .constant(lookupError != nil)) {
            Button("OK") { lookupError = nil }
        } message: { Text(lookupError ?? "") }
    }

    private func loadLowStock() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            lowStock = try await client.searchRead(
                model: "stock.quant",
                domain: [
                    .array([.string("location_id.usage"), .string("="), .string("internal")]),
                    .array([.string("quantity"), .string("<="), .int(5)])
                ],
                fields: StockQuant.fields,
                limit: 50,
                order: "quantity asc"
            )
        } catch {
            lowStock = []
        }
    }

    private func runSearch() async {
        guard let client = auth.client else { return }
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { searchResults = []; return }
        do {
            searchResults = try await client.searchRead(
                model: "product.product",
                domain: [
                    .string("|"), .string("|"),
                    .array([.string("name"), .string("ilike"), .string(needle)]),
                    .array([.string("default_code"), .string("ilike"), .string(needle)]),
                    .array([.string("barcode"), .string("="), .string(needle)])
                ],
                fields: ProductDetail.fields,
                limit: 50,
                order: "name asc"
            )
        } catch {
            searchResults = []
        }
    }

    private func handleScan(_ code: String) async {
        guard let client = auth.client else { return }
        do {
            let matches: [ProductDetail] = try await client.searchRead(
                model: "product.product",
                domain: [.array([.string("barcode"), .string("="), .string(code)])],
                fields: ProductDetail.fields,
                limit: 1
            )
            if let match = matches.first {
                adjustingProduct = match
            } else {
                lookupError = "Kein Produkt mit Barcode \(code)."
            }
        } catch {
            lookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadProduct(id: Int) async {
        guard let client = auth.client else { return }
        do {
            let matches: [ProductDetail] = try await client.searchRead(
                model: "product.product",
                domain: [.array([.string("id"), .string("="), .int(id)])],
                fields: ProductDetail.fields,
                limit: 1
            )
            adjustingProduct = matches.first
        } catch {
            lookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
