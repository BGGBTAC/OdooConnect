import SwiftUI

struct ShippingListView: View {
    @Environment(AuthManager.self) private var auth
    @State private var model = ShippingViewModel()

    var body: some View {
        List {
            Picker("Status", selection: Binding(
                get: { model.filter },
                set: { model.filter = $0 }
            )) {
                ForEach(ShippingViewModel.StateFilter.allCases) { state in
                    Text(state.label).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)

            ForEach(model.pickings) { picking in
                NavigationLink(value: picking) {
                    ShippingRow(picking: picking)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Versand")
        .searchable(text: Binding(
            get: { model.searchText },
            set: { model.searchText = $0 }
        ), prompt: "Nummer, Quelle, Kunde")
        .task(id: taskKey) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.load(using: auth.client)
        }
        .refreshable { await model.load(using: auth.client) }
        .navigationDestination(for: StockPicking.self) { picking in
            ShipmentDetailView(pickingId: picking.id)
        }
        .navigationDestination(for: AppRouter.ShippingRoute.self) { route in
            switch route {
            case .detail(let id): ShipmentDetailView(pickingId: id)
            }
        }
        .overlay {
            if model.pickings.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    "Keine Lieferungen",
                    systemImage: "shippingbox",
                    description: Text(model.error ?? "Keine Treffer für den Filter.")
                )
            }
        }
    }

    private var taskKey: String {
        "\(model.filter.rawValue)|\(model.searchText)"
    }
}

struct ShippingRow: View {
    let picking: StockPicking

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(picking.name).font(.headline)
                    if let origin = picking.origin {
                        Text("· \(origin)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if let partner = picking.partner_id, !partner.isEmpty {
                    Text(partner.name).font(.subheadline).foregroundStyle(.secondary)
                }
                if let date = picking.scheduled_date ?? picking.date_done {
                    Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(picking.stateLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
                if let tracking = picking.carrier_tracking_ref {
                    Text(tracking).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
    }

    private var icon: String {
        switch picking.state {
        case "done":     return "checkmark.seal.fill"
        case "assigned": return "shippingbox.fill"
        case "cancel":   return "xmark.circle.fill"
        default:         return "clock.badge"
        }
    }

    private var tint: Color {
        switch picking.state {
        case "done":     return .green
        case "assigned": return .blue
        case "cancel":   return .red
        case "waiting", "confirmed": return .orange
        default:         return .secondary
        }
    }
}
