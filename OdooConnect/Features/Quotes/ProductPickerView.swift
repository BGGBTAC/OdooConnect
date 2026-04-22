import SwiftUI

struct ProductPickerView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var products: [Product] = []
    @State private var query: String = ""
    @State private var isLoading = false

    let onSelect: (Product) -> Void

    var body: some View {
        NavigationStack {
            List(products) { product in
                Button {
                    onSelect(product)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.headline).foregroundStyle(.primary)
                            if let code = product.default_code {
                                Text(code).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(product.list_price, format: .currency(code: "EUR"))
                            .monospacedDigit().foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Name oder Artikelnummer")
            .onChange(of: query) { _, _ in Task { await search() } }
            .task { await search() }
            .overlay { if isLoading && products.isEmpty { ProgressView() } }
            .navigationTitle("Produkte")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var domain: [JSON] = [.array([.string("sale_ok"), .string("="), .bool(true)])]
        if !trimmed.isEmpty {
            domain = [
                .array([.string("sale_ok"), .string("="), .bool(true)]),
                .string("|"),
                .array([.string("name"), .string("ilike"), .string(trimmed)]),
                .array([.string("default_code"), .string("ilike"), .string(trimmed)])
            ]
        }
        do {
            products = try await client.searchRead(
                model: "product.product",
                domain: domain,
                fields: Product.fields,
                limit: 100,
                order: "name asc"
            )
        } catch {
            products = []
        }
    }
}
