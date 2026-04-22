import SwiftUI
import PencilKit

/// Modal canvas for capturing an Apple Pencil / finger signature. The
/// rendered drawing is returned as a PNG `Data` payload to the caller via
/// `onSave` — the caller is responsible for uploading it (e.g. as an
/// `ir.attachment` linked to the originating record).
struct SignatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (Data) async -> Void

    @State private var canvasView = PKCanvasView()
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CanvasRepresentable(canvas: canvasView)
                    .background(.background)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.secondary.opacity(0.4))
                            .frame(height: 1)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                            .accessibilityHidden(true)
                    }

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Löschen", systemImage: "trash") {
                        canvasView.drawing = PKDrawing()
                    }
                    .accessibilityLabel("Unterschrift löschen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Speichern") { Task { await save() } }
                            .disabled(canvasView.drawing.bounds.isEmpty)
                    }
                }
            }
        }
    }

    private func save() async {
        let drawing = canvasView.drawing
        guard !drawing.bounds.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let bounds = drawing.bounds.insetBy(dx: -16, dy: -16)
        let image = drawing.image(from: bounds, scale: 2.0)
        guard let png = image.pngData() else {
            error = "Bild konnte nicht gerendert werden."
            return
        }
        await onSave(png)
        dismiss()
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 2)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
