import SwiftUI

/// Posteingang — incoming customer messages from Odoo. Phase 1: read +
/// notify. Tapping a message opens the read-only thread for its record.
/// (Replying from the app comes later.)
struct InboxView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(OrderWatcher.self) private var orderWatcher
    @State private var model = InboxViewModel()
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(filtered) { message in
                NavigationLink(value: message) {
                    InboxRow(message: message)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Posteingang")
            .navigationDestination(for: InboxMessage.self) { message in
                InboxThreadView(message: message)
            }
            .searchable(text: $search, prompt: "Kunde oder Betreff")
            .searchToolbarBehavior(.minimize)
            .refreshable { await model.load(using: auth.client) }
            .task { await model.load(using: auth.client) }
            .overlay {
                if model.messages.isEmpty && !model.isLoading {
                    ContentUnavailableView(
                        "Keine Nachrichten",
                        systemImage: "tray",
                        description: Text(model.error ?? "Hier erscheinen Antworten deiner Kunden aus Odoo.")
                    )
                }
            }
            .errorAlert(error: Bindable(model).error)
        }
        // Visiting the inbox clears the unread badge.
        .onAppear { orderWatcher.clearMessageUnread() }
    }

    private var filtered: [InboxMessage] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.messages }
        return model.messages.filter {
            $0.authorName.lowercased().contains(q)
                || $0.subject.lowercased().contains(q)
                || $0.recordName.lowercased().contains(q)
        }
    }
}

private struct InboxRow: View {
    let message: InboxMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.authorName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(message.date, style: .relative)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !message.subject.isEmpty {
                Text(message.subject)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !message.preview.isEmpty {
                Text(message.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !message.recordName.isEmpty {
                Label(message.recordName, systemImage: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Read-only thread for one record's chatter (model + res_id).
struct InboxThreadView: View {
    let message: InboxMessage
    @Environment(AuthManager.self) private var auth
    @State private var vm = InboxViewModel()
    @State private var thread: [InboxMessage] = []
    @State private var isLoading = false

    private var entries: [InboxMessage] {
        thread.isEmpty ? [message] : thread
    }

    var body: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.authorName)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if !entry.subject.isEmpty {
                            Text(entry.subject)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.preview.isEmpty ? "(kein Textinhalt)" : entry.preview)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                if !message.recordName.isEmpty {
                    Text(message.recordName)
                }
            }
        }
        .navigationTitle(message.authorName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && thread.isEmpty {
                ProgressView()
            }
        }
        .task {
            guard let model = message.model else { return }
            isLoading = true
            thread = await vm.thread(model: model, resId: message.resId, using: auth.client)
            isLoading = false
        }
    }
}
