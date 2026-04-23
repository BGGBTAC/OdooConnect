import SwiftUI

/// Modal carrier picker. Reads the list from the model that's already
/// fetched it; the parent view wires the selection back into a binding.
struct CarrierPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let carriers: [DeliveryCarrier]
    let currentCarrierId: Int?
    let onSelect: (DeliveryCarrier?) -> Void

    @State private var query: String = ""

    private var filtered: [DeliveryCarrier] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return carriers }
        return carriers.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.slate)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kein Versender").foregroundStyle(.primary)
                                Text("Picking ohne Carrier-Zuweisung")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if currentCarrierId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section("Verfügbar") {
                    if filtered.isEmpty {
                        Text(carriers.isEmpty ? "Keine Versender konfiguriert."
                                              : "Keine Treffer.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { carrier in
                            Button {
                                onSelect(carrier)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "shippingbox.and.arrow.backward")
                                        .foregroundStyle(Theme.brand)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(carrier.name).foregroundStyle(.primary)
                                        if let subtitle = carrier.subtitle {
                                            Text(subtitle)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if carrier.id == currentCarrierId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.brand)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Versender wählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Carrier suchen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
