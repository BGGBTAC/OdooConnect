import SwiftUI
import SwiftData

private enum EditorMode: Identifiable {
    case new
    case edit(DraftQuote)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let draft): return draft.id.uuidString
        }
    }
}

struct QuotesListView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(DraftSync.self) private var draftSync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(
        sort: \DraftQuote.createdAt,
        order: .reverse
    ) private var drafts: [DraftQuote]

    @State private var model = QuotesViewModel()
    @State private var editorMode: EditorMode?
    @State private var searchText = ""
    @State private var draftPendingDeletion: DraftQuote?
    @State private var showDeleteDialog = false

    var body: some View {
        List {
            if !filteredDrafts.isEmpty {
                Section("Lokale Entwürfe") {
                    ForEach(filteredDrafts) { draft in
                        Button {
                            editorMode = .edit(draft)
                        } label: {
                            DraftRow(draft: draft)
                        }
                        .buttonStyle(.plain)
                        .transition(rowTransition)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                draftPendingDeletion = draft
                                showDeleteDialog = true
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            if draft.status == .failed {
                                Button {
                                    // Reset before sync so a dead-lettered
                                    // draft (attempts >= max) re-enters the
                                    // outbox queue instead of being skipped.
                                    draft.status = .pending
                                    draft.attempts = 0
                                    draft.lastError = nil
                                    try? modelContext.save()
                                    Task { await draftSync.sync() }
                                } label: {
                                    Label("Erneut", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            Section(filteredDrafts.isEmpty ? "" : "Synchronisiert") {
                ForEach(model.quotes) { quote in
                    NavigationLink(value: quote) {
                        QuoteRow(quote: quote)
                    }
                }
            }
        }
        .navigationTitle("Angebote")
        .searchable(text: $searchText, prompt: "Kunde oder Nummer")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorMode = .new
                } label: {
                    Label("Neu", systemImage: "plus")
                }
            }
            if draftSync.isSyncing {
                ToolbarItem(placement: .status) {
                    ProgressView()
                }
            }
        }
        .refreshable {
            await draftSync.sync()
            await model.load(using: auth.client, search: searchText)
        }
        .task(id: searchText) {
            // Debounce so each keystroke doesn't fire a request.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.load(using: auth.client, search: searchText)
        }
        .onChange(of: draftSync.lastSyncedAt) { _, _ in
            Task { await model.load(using: auth.client, search: searchText) }
        }
        .navigationDestination(for: SaleOrder.self) { quote in
            OrderDetailView(orderId: quote.id)
        }
        .sheet(item: $editorMode) { mode in
            NavigationStack {
                switch mode {
                case .new: QuoteEditorView()
                case .edit(let draft): QuoteEditorView(draft: draft)
                }
            }
            .presentationSizing(.form)
        }
        .overlay {
            if model.quotes.isEmpty && filteredDrafts.isEmpty && !model.isLoading {
                BrandedEmptyState(
                    title: searchText.isEmpty ? "Noch keine Angebote" : "Keine Treffer",
                    systemImage: "doc.text",
                    message: searchText.isEmpty
                        ? "Tippe auf + um ein neues Angebot zu erstellen."
                        : "Versuche einen anderen Suchbegriff."
                )
            }
        }
        .confirmationDialog(
            "Entwurf löschen?",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible,
            presenting: draftPendingDeletion
        ) { draft in
            Button("Löschen", role: .destructive) {
                withAnimation(.smooth) {
                    modelContext.delete(draft)
                    try? modelContext.save()
                }
                draftPendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { draftPendingDeletion = nil }
        } message: { draft in
            Text("„\(draft.partnerName)“ wurde noch nicht mit Odoo synchronisiert und kann nicht wiederhergestellt werden.")
        }
    }

    private var filteredDrafts: [DraftQuote] {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return drafts }
        return drafts.filter { $0.partnerName.lowercased().contains(needle) }
    }

    private var rowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
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
                Text(quote.amount_total, format: .currency(code: quote.currency_id.name))
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

private struct DraftRow: View {
    let draft: DraftQuote

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.partnerName).font(.headline)
                Text(draft.createdAt, style: .relative)
                    .font(.caption).foregroundStyle(.secondary)
                if draft.status == .failed, let lastError = draft.lastError {
                    Text(lastError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(draft.total, format: .currency(code: draft.currencyCode))
                    .font(.headline.monospacedDigit())
                StatusBadge(draft: draft)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct StatusBadge: View {
    let draft: DraftQuote
    private var status: DraftStatus { draft.status }
    private var isDead: Bool { draft.isDeadLettered }

    var body: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon)
                .contentTransition(.symbolEffect(.replace))
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .glassEffect(.regular.tint(tint.opacity(isDead ? 0.28 : 0.18)), in: .capsule)
        .accessibilityLabel(label)
        .animation(.snappy, value: status)
    }

    private var label: String {
        if isDead { return "Endgültig fehlgeschlagen" }
        switch status {
        case .pending: return "Wartet"
        case .sending: return "Wird gesendet"
        case .failed: return "Fehlgeschlagen"
        case .synced: return "Gesendet"
        }
    }

    private var icon: String {
        if isDead { return "xmark.octagon.fill" }
        switch status {
        case .pending: return "clock"
        case .sending: return "arrow.up.circle"
        case .failed: return "exclamationmark.triangle"
        case .synced: return "checkmark.circle"
        }
    }

    // .failed shows orange (will retry); dead-lettered shows red (terminal).
    private var tint: Color {
        if isDead { return .red }
        switch status {
        case .pending: return .secondary
        case .sending: return .blue
        case .failed: return .orange
        case .synced: return .green
        }
    }
}
