import SwiftUI

struct ProductPickerView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var products: [Product] = []
    @State private var query: String = ""
    @State private var isLoading = false
    @State private var error: String?

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
                        Text(product.list_price, format: .currency(code: auth.companyCurrency.code))
                            .monospacedDigit().foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
            }
            .searchable(text: $query, prompt: "Name oder Artikelnummer")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await search()
            }
            .overlay {
                if isLoading && products.isEmpty { ProgressView() }
                if let error, products.isEmpty {
                    ContentUnavailableView(
                        "Fehler",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                }
            }
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
        error = nil
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
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            products = []
        }
    }
}
