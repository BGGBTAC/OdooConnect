import SwiftUI

struct PartnerPickerView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var partners: [Partner] = []
    @State private var query: String = ""
    @State private var isLoading = false

    let onSelect: (Partner) -> Void

    var body: some View {
        NavigationStack {
            List(partners) { partner in
                Button {
                    onSelect(partner)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(partner.name).font(.headline).foregroundStyle(.primary)
                        if let email = partner.email {
                            Text(email).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let city = partner.city {
                            Text(city).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Name, E‑Mail, Stadt")
            .onChange(of: query) { _, _ in Task { await search() } }
            .task { await search() }
            .overlay { if isLoading && partners.isEmpty { ProgressView() } }
            .navigationTitle("Kunden")
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
        var domain: [JSON] = [.array([.string("customer_rank"), .string(">"), .int(0)])]
        if !trimmed.isEmpty {
            domain = [
                .string("|"), .string("|"),
                .array([.string("name"), .string("ilike"), .string(trimmed)]),
                .array([.string("email"), .string("ilike"), .string(trimmed)]),
                .array([.string("city"), .string("ilike"), .string(trimmed)])
            ]
        }
        do {
            partners = try await client.searchRead(
                model: "res.partner",
                domain: domain,
                fields: Partner.fields,
                limit: 100,
                order: "name asc"
            )
        } catch {
            partners = []
        }
    }
}
