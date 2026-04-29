import SwiftUI

struct InventoryAdjustmentSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let product: ProductDetail
    let onApplied: () async -> Void

    @State private var quants: [StockQuant] = []
    @State private var selectedQuant: StockQuant?
    @State private var newQuantity: Double = 0
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var error: String?
    @State private var showingTransfer = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name).font(.title3.bold())
                    if let code = product.default_code {
                        Text(code).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        Label("\(Int(product.qty_available))",
                              systemImage: "cube.box.fill")
                            .foregroundStyle(product.qty_available <= 0 ? .red : .green)
                        if product.incoming_qty > 0 {
                            Label("+\(Int(product.incoming_qty))", systemImage: "arrow.down.to.line")
                                .foregroundStyle(.teal)
                        }
                        if product.outgoing_qty > 0 {
                            Label("-\(Int(product.outgoing_qty))", systemImage: "arrow.up.from.line")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if product.requiresLotOrSerial {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.tracking == "serial"
                                 ? "Seriennummer-pflichtig"
                                 : "Lot-pflichtig")
                                .font(.subheadline.weight(.semibold))
                            Text("Bestandskorrekturen für dieses Produkt verlangen eine Lot/Serien-Zuweisung. Bitte direkt im Odoo-Web-Client durchführen — die App kann den Wizard nicht abschließen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "barcode.viewfinder")
                            .foregroundStyle(Theme.warning)
                    }
                }
            }

            Section("Lagerort") {
                if quants.isEmpty && !isLoading {
                    Text("Kein Bestand an internen Lagerorten. Bitte Standort zuerst in Odoo einrichten.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(quants) { quant in
                        Button {
                            selectedQuant = quant
                            newQuantity = quant.quantity
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(quant.location_id.name).font(.subheadline.weight(.semibold))
                                    Text("Verfügbar: \(quant.available_quantity, specifier: "%.0f")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedQuant?.id == quant.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                                Text("\(quant.quantity, specifier: "%.0f")")
                                    .font(.headline.monospacedDigit())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if selectedQuant != nil {
                Section("Neue Menge") {
                    HStack {
                        Stepper(value: $newQuantity, in: 0...9999, step: 1) {
                            Text("Anzahl")
                        }
                        TextField("", value: $newQuantity, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 80)
                    }
                }

                Section {
                    Button {
                        Task { await apply() }
                    } label: {
                        HStack {
                            if isApplying { ProgressView() }
                            else { Image(systemName: "arrow.triangle.2.circlepath") }
                            Text("Bestand anpassen").bold()
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isApplying || product.requiresLotOrSerial)
                }
            }
        }
        .navigationTitle("Bestand anpassen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingTransfer = true
                } label: {
                    Label("Umlagern", systemImage: "arrow.left.arrow.right")
                }
            }
        }
        .task { await loadQuants() }
        .sheet(isPresented: $showingTransfer) {
            NavigationStack {
                StockTransferSheet(product: product) {
                    await loadQuants()
                    await onApplied()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .errorAlert(error: $error)
    }

    private func loadQuants() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            quants = try await client.searchRead(
                model: "stock.quant",
                domain: [
                    .array([.string("product_id"), .string("="), .int(product.id)]),
                    .array([.string("location_id.usage"), .string("="), .string("internal")])
                ],
                fields: StockQuant.fields,
                limit: 20,
                order: "quantity desc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply() async {
        guard let client = auth.client, let quant = selectedQuant else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            _ = try await client.writeWithGuard(
                model: "stock.quant",
                id: quant.id,
                values: ["inventory_quantity": .double(newQuantity)],
                lastSeenWriteDate: quant.write_date ?? .distantPast
            )
            let _: JSON = try await client.callKw(
                model: "stock.quant",
                method: "action_apply_inventory",
                args: [.array([.int(quant.id)])]
            )
            await onApplied()
            dismiss()
        } catch OdooError.conflict {
            // Server-wins: the quant already moved (someone else
            // committed an adjustment / reservation / picking). Reload
            // and tell the user to redo with fresh numbers.
            self.error = "Der Bestand wurde gerade von einer anderen Stelle geändert. Die Liste wird neu geladen — bitte korrigiere noch einmal."
            await loadQuants()
            selectedQuant = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
