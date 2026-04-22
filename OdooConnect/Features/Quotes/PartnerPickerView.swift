import SwiftUI

struct PartnerPickerView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var partners: [Partner] = []
    @State private var query: String = ""
    @State private var isLoading = false
    @State private var error: String?

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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            .searchable(text: $query, prompt: "Name, E‑Mail, Stadt")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await search()
            }
            .overlay {
                if isLoading && partners.isEmpty { ProgressView() }
                if let error, partners.isEmpty {
                    ContentUnavailableView(
                        "Fehler",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                }
            }
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
        error = nil
        defer { isLoading = false }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var domain: [JSON] = [.array([.string("customer_rank"), .string(">"), .int(0)])]
        if !trimmed.isEmpty {
            domain = [
                .array([.string("customer_rank"), .string(">"), .int(0)]),
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
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            partners = []
        }
    }
}
