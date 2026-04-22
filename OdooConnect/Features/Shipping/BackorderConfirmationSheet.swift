import SwiftUI

/// Native handler for Odoo's `stock.backorder.confirmation` wizard. When a
/// `button_validate` call returns an action targeting that wizard model we
/// create the wizard record on the fly and let the user pick whether to
/// process with a backorder, without one, or cancel.
struct BackorderConfirmationSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let pickingId: Int
    let pickingName: String
    let onCompleted: (String) async -> Void

    @State private var isProcessing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                    .padding(.top, 24)

                Text("Backorder erforderlich")
                    .font(.title3.bold())

                Text("Für die Lieferung **\(pickingName)** wurden nicht alle Mengen vollständig versendet. Wie soll der Restbestand behandelt werden?")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer(minLength: 12)

                VStack(spacing: 12) {
                    Button {
                        Task { await process(createBackorder: true) }
                    } label: {
                        actionLabel("Versenden + Backorder anlegen", system: "shippingbox.and.arrow.backward.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isProcessing)

                    Button {
                        Task { await process(createBackorder: false) }
                    } label: {
                        actionLabel("Versenden, Restbestand verwerfen", system: "trash")
                    }
                    .buttonStyle(.glass)
                    .disabled(isProcessing)
                }
                .padding(.horizontal)

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)
            }
            .navigationTitle("Bestätigung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isProcessing)
                }
                if isProcessing {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                    }
                }
            }
        }
    }

    private func actionLabel(_ title: String, system: String) -> some View {
        HStack {
            Image(systemName: system)
            Text(title).bold()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func process(createBackorder: Bool) async {
        guard let client = auth.client else { return }
        isProcessing = true
        error = nil
        defer { isProcessing = false }
        do {
            let wizardId = try await client.create(
                model: "stock.backorder.confirmation",
                values: [
                    "pick_ids": .array([
                        .array([.int(6), .int(0), .array([.int(pickingId)])])
                    ])
                ]
            )
            let method = createBackorder ? "process" : "process_cancel_backorder"
            let _: JSON = try await client.callKw(
                model: "stock.backorder.confirmation",
                method: method,
                args: [.array([.int(wizardId)])]
            )
            await onCompleted(createBackorder
                ? "Lieferung versendet, Backorder angelegt."
                : "Lieferung versendet, Restmenge verworfen.")
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
