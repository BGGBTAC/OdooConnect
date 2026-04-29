import SwiftUI

/// Multi-select picker for sale-side `account.tax` records. Used by the
/// quote editor when the user wants to override Odoo's onchange defaults
/// for a specific line.
struct TaxPickerSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    /// The IDs the editor row already holds. Pre-checked on appear.
    let initialSelection: Set<Int>
    let onSelect: (_ taxes: [OdooTax]) -> Void

    @State private var taxes: [OdooTax] = []
    @State private var selection: Set<Int> = []
    @State private var query: String = ""
    @State private var isLoading = false
    @State private var error: String?

    init(
        initialSelection: Set<Int>,
        onSelect: @escaping (_ taxes: [OdooTax]) -> Void
    ) {
        self.initialSelection = initialSelection
        self.onSelect = onSelect
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            selection.removeAll()
                        } label: {
                            Label("Auswahl leeren (Odoo-Default verwenden)", systemImage: "arrow.uturn.left")
                        }
                    }
                }
                Section {
                    ForEach(filteredTaxes) { tax in
                        Button {
                            toggle(tax.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tax.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(tax.shortLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection.contains(tax.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.brand)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    if !filteredTaxes.isEmpty {
                        Text("Verfügbare Steuern")
                    }
                } footer: {
                    Text("Leere Auswahl = Odoo verwendet seine Default-Steuern automatisch beim Speichern.")
                        .font(.caption)
                }
            }
            .searchable(text: $query, prompt: "Steuern suchen")
            .overlay {
                if isLoading && taxes.isEmpty {
                    ProgressView()
                } else if let error, taxes.isEmpty {
                    ContentUnavailableView(
                        "Fehler",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if taxes.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "Keine Steuern",
                        systemImage: "percent",
                        description: Text("Es sind keine Sale-Steuern in diesem Odoo-System konfiguriert.")
                    )
                }
            }
            .navigationTitle("Steuern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        let picked = taxes.filter { selection.contains($0.id) }
                        onSelect(picked)
                        dismiss()
                    }
                }
            }
            .task { await load() }
        }
    }

    private var filteredTaxes: [OdooTax] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return taxes }
        return taxes.filter { $0.name.lowercased().contains(trimmed) }
    }

    private func toggle(_ id: Int) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func load() async {
        guard taxes.isEmpty, let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            taxes = try await client.searchRead(
                model: "account.tax",
                domain: [
                    .array([.string("type_tax_use"), .string("="), .string("sale")])
                ],
                fields: OdooTax.fields,
                limit: 200,
                order: "sequence asc, id asc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
