import SwiftUI

/// Internal stock transfer between two locations. Creates a `stock.picking`
/// of type `internal` with one embedded move, then confirms / assigns /
/// validates it. If Odoo opens an "immediate transfer" or backorder wizard
/// during validate we surface it as a hint and refresh.
struct StockTransferSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let product: ProductDetail
    let onCompleted: () async -> Void

    @State private var sources: [StockQuant] = []
    @State private var sourceQuant: StockQuant?
    @State private var destinations: [StockLocation] = []
    @State private var destination: StockLocation?
    @State private var quantity: Double = 1
    @State private var pickingType: PickingType?
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var info: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(.title3.bold())
                    if let code = product.default_code {
                        Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Quelle") {
                if sources.isEmpty && !isLoading {
                    Text("Kein verfügbarer Bestand auf internen Standorten.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources) { quant in
                        Button {
                            sourceQuant = quant
                            quantity = min(max(quant.available_quantity, 0), 1)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(quant.location_id.name).font(.subheadline.weight(.semibold))
                                    Text("Verfügbar: \(quant.available_quantity, specifier: "%.0f")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if sourceQuant?.id == quant.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Ziel") {
                if let destination {
                    HStack {
                        Text(destination.display_name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Ändern") { self.destination = nil }
                            .font(.caption)
                    }
                } else {
                    DestinationPicker(
                        excludingId: sourceQuant?.location_id.id,
                        destinations: destinations
                    ) { picked in
                        destination = picked
                    }
                }
            }

            if sourceQuant != nil, destination != nil {
                Section("Menge") {
                    HStack {
                        Stepper(value: $quantity,
                                in: 0.01...(sourceQuant?.available_quantity ?? 9999),
                                step: 1) {
                            Text("Anzahl")
                        }
                        TextField("", value: $quantity, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 80)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView() }
                            else { Image(systemName: "arrow.left.arrow.right") }
                            Text("Umlagerung ausführen").bold()
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isSubmitting || !canSubmit)
                }
            }
        }
        .navigationTitle("Umlagerung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
        }
        .task { await load() }
        .errorAlert(error: $error)
        .alert(
            "Hinweis",
            isPresented: Binding(
                get: { info != nil },
                set: { if !$0 { info = nil } }
            )
        ) {
            Button("OK") { info = nil; dismiss() }
        } message: { Text(info ?? "") }
    }

    private var canSubmit: Bool {
        sourceQuant != nil
            && destination != nil
            && pickingType != nil
            && quantity > 0
            && quantity <= (sourceQuant?.available_quantity ?? 0)
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }

        async let sourcesTask: [StockQuant] = client.searchRead(
            model: "stock.quant",
            domain: [
                .array([.string("product_id"), .string("="), .int(product.id)]),
                .array([.string("location_id.usage"), .string("="), .string("internal")]),
                .array([.string("available_quantity"), .string(">"), .int(0)])
            ],
            fields: StockQuant.fields,
            limit: 30,
            order: "available_quantity desc"
        )
        async let destinationsTask: [StockLocation] = client.searchRead(
            model: "stock.location",
            domain: [.array([.string("usage"), .string("="), .string("internal")])],
            fields: StockLocation.fields,
            limit: 200,
            order: "complete_name asc"
        )
        async let pickingTypeTask: [PickingType] = client.searchRead(
            model: "stock.picking.type",
            domain: [.array([.string("code"), .string("="), .string("internal")])],
            fields: PickingType.fields,
            limit: 1,
            order: "sequence asc, id asc"
        )

        do {
            self.sources = try await sourcesTask
            self.destinations = try await destinationsTask
            self.pickingType = try await pickingTypeTask.first
            if pickingType == nil {
                error = "Kein interner Liefer-Typ konfiguriert. Bitte in Odoo unter Lager → Konfiguration einen `Internal Transfers` Typ anlegen."
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func submit() async {
        guard
            let client = auth.client,
            let sourceQuant,
            let destination,
            let pickingType
        else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        error = nil

        let uomId = product.uom_id?.id ?? 1
        let move: JSON = .array([
            .int(0), .int(0),
            .object([
                "name": .string(product.name),
                "product_id": .int(product.id),
                "product_uom_qty": .double(quantity),
                "product_uom": .int(uomId),
                "location_id": .int(sourceQuant.location_id.id),
                "location_dest_id": .int(destination.id)
            ])
        ])

        do {
            let pickingId = try await client.create(
                model: "stock.picking",
                values: [
                    "picking_type_id": .int(pickingType.id),
                    "location_id": .int(sourceQuant.location_id.id),
                    "location_dest_id": .int(destination.id),
                    "move_ids": .array([move])
                ]
            )
            let _: JSON = try await client.callKw(
                model: "stock.picking",
                method: "action_confirm",
                args: [.array([.int(pickingId)])]
            )
            let _: JSON = try await client.callKw(
                model: "stock.picking",
                method: "action_assign",
                args: [.array([.int(pickingId)])]
            )
            // Pre-fill the move line quantity so button_validate doesn't open
            // the immediate-transfer wizard for nothing.
            try await prefillMoveLine(client: client, pickingId: pickingId)

            let result: JSON = try await client.callKw(
                model: "stock.picking",
                method: "button_validate",
                args: [.array([.int(pickingId)])]
            )
            if case .object(let dict) = result,
               case .string(let model)? = dict["res_model"] {
                info = "Umlagerung angelegt — Odoo verlangt Bestätigung im \(model)-Wizard. Bitte in der Weboberfläche abschließen."
            } else {
                info = "Umlagerung erfolgreich."
            }
            await onCompleted()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// On Odoo 17+ `stock.move.line.quantity` is the field that "books" the
    /// transfer. If we don't write it, button_validate opens the
    /// immediate-transfer wizard.
    private func prefillMoveLine(client: OdooClient, pickingId: Int) async throws {
        let lines: [StockMoveLine] = try await client.searchRead(
            model: "stock.move.line",
            domain: [.array([.string("picking_id"), .string("="), .int(pickingId)])],
            fields: StockMoveLine.fields,
            limit: 50
        )
        let ids = lines.map { $0.id }
        guard !ids.isEmpty else { return }
        _ = try await client.write(
            model: "stock.move.line",
            ids: ids,
            values: ["quantity": .double(quantity)]
        )
    }
}

private struct DestinationPicker: View {
    let excludingId: Int?
    let destinations: [StockLocation]
    let onPick: (StockLocation) -> Void
    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Standort suchen", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            ForEach(filtered) { location in
                Button {
                    onPick(location)
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                        Text(location.display_name)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                if location.id != filtered.last?.id {
                    Divider()
                }
            }
            if filtered.isEmpty {
                Text("Keine Treffer.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var filtered: [StockLocation] {
        let pool = destinations.filter { $0.id != excludingId }
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return Array(pool.prefix(20)) }
        return pool.filter { $0.display_name.lowercased().contains(trimmed) }.prefix(20).map { $0 }
    }
}
