import SwiftUI

struct ShipmentDetailView: View {
    @Environment(AuthManager.self) private var auth
    let pickingId: Int

    @State private var picking: StockPicking?
    @State private var moves: [StockMoveLine] = []
    @State private var isLoading = false
    @State private var isValidating = false
    @State private var error: String?
    @State private var info: String?
    @State private var showingBackorderSheet = false

    var body: some View {
        List {
            if let picking {
                Section {
                    LabeledContent("Nummer", value: picking.name)
                    if let origin = picking.origin {
                        LabeledContent("Quelle", value: origin)
                    }
                    if let partner = picking.partner_id, !partner.isEmpty {
                        LabeledContent("Kunde", value: partner.name)
                    }
                    if let carrier = picking.carrier_id, !carrier.isEmpty {
                        LabeledContent("Versender", value: carrier.name)
                    }
                    LabeledContent("Status", value: picking.stateLabel)
                    if let date = picking.scheduled_date {
                        LabeledContent("Geplant", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let done = picking.date_done {
                        LabeledContent("Versendet", value: done.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                if let tracking = picking.carrier_tracking_ref {
                    Section("Tracking") {
                        HStack {
                            Text(tracking).font(.body.monospaced())
                            Spacer()
                            Button {
                                UIPasteboard.general.string = tracking
                                info = "Tracking-Nummer kopiert."
                            } label: {
                                Label("Kopieren", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.glass)
                            .labelStyle(.iconOnly)
                        }
                    }
                }

                Section("Positionen") {
                    ForEach(moves) { move in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(move.product_id.name).font(.subheadline.weight(.semibold))
                                if let uom = move.product_uom_id {
                                    Text(uom.name).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Text("\(move.quantity, specifier: "%.2f")")
                                .font(.headline.monospacedDigit())
                        }
                    }
                }

                if picking.isActionable {
                    Section {
                        NavigationLink {
                            OrderPickingView(
                                pickingId: picking.id,
                                pickingName: picking.name
                            ) {
                                await load()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "barcode.viewfinder")
                                Text("Pick this order")
                                    .bold()
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .listRowBackground(Theme.brand.opacity(0.10))
                        .foregroundStyle(Theme.brand)

                        Button {
                            Task { await validate(picking) }
                        } label: {
                            HStack {
                                if isValidating { ProgressView() }
                                else { Image(systemName: "checkmark.seal.fill") }
                                Text("Als versendet markieren")
                                    .bold()
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isValidating)
                    } header: {
                        Text("Aktionen")
                    } footer: {
                        Text("Pick this order: scanne Barcodes, fülle Mengen, wähle Versender und versende in einem Schritt.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(picking?.name ?? "Lieferung")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .overlay { if isLoading && picking == nil { ProgressView() } }
        .errorAlert(error: $error)
        .infoAlert(message: $info)
        .sheet(isPresented: $showingBackorderSheet) {
            if let picking {
                BackorderConfirmationSheet(
                    pickingId: picking.id,
                    pickingName: picking.name
                ) { message in
                    info = message
                    await load()
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let pickings: [StockPicking] = try await client.searchRead(
                model: "stock.picking",
                domain: [.array([.string("id"), .string("="), .int(pickingId)])],
                fields: StockPicking.fields,
                limit: 1
            )
            self.picking = pickings.first
            self.moves = try await client.searchRead(
                model: "stock.move.line",
                domain: [.array([.string("picking_id"), .string("="), .int(pickingId)])],
                fields: StockMoveLine.fields,
                limit: 500,
                order: "id asc"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func validate(_ picking: StockPicking) async {
        guard let client = auth.client else { return }
        isValidating = true
        defer { isValidating = false }
        do {
            let result: JSON = try await client.callKw(
                model: "stock.picking",
                method: "button_validate",
                args: [.array([.int(picking.id)])]
            )
            if case .object(let dict) = result,
               case .string(let model)? = dict["res_model"],
               model == "stock.backorder.confirmation" {
                showingBackorderSheet = true
            } else if case .object(let dict) = result,
                      case .string(let type)? = dict["type"],
                      type.hasPrefix("ir.actions") {
                info = "Odoo fordert eine zusätzliche Bestätigung (\(dict["res_model"]?.stringValue ?? "Wizard")). Bitte in der Weboberfläche abschließen."
                await load()
            } else {
                info = "Lieferung versendet."
                await load()
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
