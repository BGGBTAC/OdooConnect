import SwiftUI

struct QuotesListView: View {
    @Environment(AuthManager.self) private var auth
    @State private var model = QuotesViewModel()
    @State private var showingEditor = false

    var body: some View {
        List {
            ForEach(model.quotes) { quote in
                NavigationLink(value: quote) {
                    QuoteRow(quote: quote)
                }
            }
        }
        .navigationTitle("Angebote")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Neu", systemImage: "plus")
                }
            }
        }
        .refreshable { await model.load(using: auth.client) }
        .task { await model.load(using: auth.client) }
        .navigationDestination(for: SaleOrder.self) { quote in
            OrderDetailView(orderId: quote.id)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                QuoteEditorView { await model.load(using: auth.client) }
            }
        }
        .overlay {
            if model.quotes.isEmpty && !model.isLoading {
                ContentUnavailableView("Keine Angebote",
                                       systemImage: "doc.text",
                                       description: Text("Tippe auf +, um ein neues Angebot zu erstellen."))
            }
        }
    }
}

struct QuoteRow: View {
    let quote: SaleOrder

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(quote.name).font(.headline)
                Text(quote.partner_id.name).font(.subheadline).foregroundStyle(.secondary)
                Text(quote.date_order, style: .date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(quote.amount_total, format: .currency(code: "EUR"))
                    .font(.headline.monospacedDigit())
                Text(quote.stateLabel)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
