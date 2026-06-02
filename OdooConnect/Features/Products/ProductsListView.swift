import SwiftUI

struct ProductsListView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var model = ProductsViewModel()

    var body: some View {
        Group {
            if hSize == .regular {
                grid
            } else {
                list
            }
        }
        .navigationTitle("Produkte")
        .searchable(text: Binding(
            get: { model.searchText },
            set: { model.searchText = $0 }
        ), prompt: "Name, Artikelnummer, Barcode")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .task(id: debounceKey) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.load(using: auth.client)
        }
        .refreshable { await model.load(using: auth.client) }
        .navigationDestination(for: AppRouter.ProductRoute.self) { route in
            switch route {
            case .detail(let id): ProductDetailView(productId: id)
            }
        }
        .navigationDestination(for: ProductDetail.self) { product in
            ProductDetailView(productId: product.id)
        }
        .overlay {
            if model.products.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    "Keine Produkte",
                    systemImage: "shippingbox",
                    description: Text(model.error ?? "Keine Treffer für die Filter.")
                )
            }
        }
    }

    private var debounceKey: String {
        "\(model.searchText)|\(model.filter.rawValue)"
    }

    private var list: some View {
        List(model.products) { product in
            NavigationLink(value: product) {
                ProductRow(product: product, currencyCode: auth.companyCurrency.code)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(model.products) { product in
                    NavigationLink(value: product) {
                        ProductTile(product: product, currencyCode: auth.companyCurrency.code)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Bestand", selection: Binding(
                get: { model.filter },
                set: { model.filter = $0 }
            )) {
                ForEach(ProductsViewModel.StockFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
        } label: {
            Label("Filter", systemImage: model.filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

struct ProductRow: View {
    let product: ProductDetail
    let currencyCode: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.display_name).font(.headline).lineLimit(2)
                HStack(spacing: 8) {
                    if let code = product.default_code {
                        Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    if let categ = product.categ_id, !categ.isEmpty {
                        Text(categ.name).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(product.list_price, format: .currency(code: currencyCode))
                    .font(.headline.monospacedDigit())
                StockBadge(product: product)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProductTile: View {
    let product: ProductDetail
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(product.display_name).font(.headline).lineLimit(2).frame(height: 44, alignment: .topLeading)

            if let code = product.default_code {
                Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
            }

            HStack {
                Text(product.list_price, format: .currency(code: currencyCode))
                    .font(.title3.bold().monospacedDigit())
                Spacer()
                StockBadge(product: product)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }
}

struct StockBadge: View {
    let product: ProductDetail

    var body: some View {
        let (label, color) = labelAndColor
        Text(label)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var labelAndColor: (String, Color) {
        switch product.stockStateColor {
        case .healthy:    return ("\(Int(product.qty_available)) \(product.uomSymbol)", .green)
        case .low:        return ("Knapp: \(Int(product.qty_available))", .orange)
        case .outOfStock: return ("Leer", .red)
        }
    }
}
