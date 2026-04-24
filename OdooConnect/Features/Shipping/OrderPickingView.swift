import SwiftUI

/// Full-screen picking workflow for one stock.picking. Top half is the
/// scrollable list of move lines (with progress + variant info); bottom
/// half is a continuous camera scanner. Scanned barcodes are matched
/// against open lines and increment qty in place; manual override is
/// available by tapping a row.
struct OrderPickingView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let pickingId: Int
    let pickingName: String
    var onCommitted: (() async -> Void)?

    @State private var model: OrderPickingViewModel
    @State private var showCarrierSheet = false
    @State private var showingBackorderSheet = false
    @State private var selectedCarrier: DeliveryCarrier?
    @State private var carrierWasChanged = false
    @State private var manualEditingLine: PickableLine?
    @State private var manualText: String = ""
    @State private var commitMessage: String?

    init(pickingId: Int, pickingName: String, onCommitted: (() async -> Void)? = nil) {
        self.pickingId = pickingId
        self.pickingName = pickingName
        self.onCommitted = onCommitted
        _model = State(initialValue: OrderPickingViewModel(
            pickingId: pickingId, pickingName: pickingName
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            linesList
            scanner
        }
        .navigationTitle("Pick: \(pickingName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCarrierSheet = true
                } label: {
                    Label(carrierToolbarLabel, systemImage: "shippingbox.and.arrow.backward")
                }
            }
        }
        .task {
            await model.load(using: auth.client)
            await model.loadCarriers(using: auth.client)
            preselectCarrier()
        }
        .refreshable { await model.load(using: auth.client) }
        .sheet(isPresented: $showCarrierSheet) {
            CarrierPickerSheet(
                carriers: model.availableCarriers,
                currentCarrierId: carrierWasChanged ? selectedCarrier?.id : model.currentCarrier?.id
            ) { picked in
                selectedCarrier = picked
                carrierWasChanged = true
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingBackorderSheet) {
            BackorderConfirmationSheet(
                pickingId: pickingId,
                pickingName: pickingName
            ) { message in
                commitMessage = message
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $manualEditingLine) { line in
            ManualQuantitySheet(
                line: line,
                text: $manualText
            ) { newQty in
                model.setQuantity(newQty, for: line.moveId)
                manualEditingLine = nil
            }
            .presentationDetents([.height(220)])
        }
        .alert(
            "Hinweis",
            isPresented: Binding(
                get: { commitMessage != nil },
                set: { if !$0 { commitMessage = nil } }
            )
        ) {
            Button("OK") {
                commitMessage = nil
                Task {
                    await onCommitted?()
                    dismiss()
                }
            }
        } message: { Text(commitMessage ?? "") }
        .errorAlert(error: Bindable(model).error)
    }

    // MARK: - Header

    private var progressHeader: some View {
        let demand = model.totalDemand
        let picked = model.totalPicked
        let progress = demand > 0 ? min(1, picked / demand) : 0
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pick-Fortschritt")
                    .font(.caption.weight(.bold))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatted(picked)) / \(formatted(demand))")
                    .font(.subheadline.bold().monospacedDigit())
                    .contentTransition(.numericText(value: picked))
            }
            ProgressView(value: progress)
                .tint(model.allPicked ? Theme.success : Theme.brand)
                .animation(.snappy, value: progress)
            Button {
                Task { await commit() }
            } label: {
                HStack {
                    if model.isCommitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text(model.allPicked ? "Versenden" : "Auch teilweise versenden")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.right").opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity)
                .background(model.allPicked ? Theme.success : Theme.brand,
                            in: .capsule)
                .opacity(model.isCommitting ? 0.55 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(model.isCommitting || model.totalPicked == 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(.bar)
    }

    // MARK: - Lines list

    private var linesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(model.lines) { line in
                        PickLineRow(line: line) {
                            manualText = formatted(line.picked)
                            manualEditingLine = line
                        }
                        .id(line.moveId)
                    }
                    if model.lines.isEmpty && !model.isLoading {
                        BrandedEmptyState(
                            title: "Keine Positionen",
                            systemImage: "list.bullet.clipboard",
                            message: "Diese Lieferung enthält keine pickbaren Move-Lines."
                        )
                    }
                }
                .padding(Spacing.lg)
            }
            .onChange(of: model.lastScanFlash?.id) { _, _ in
                if let flash = model.lastScanFlash, flash.kind == .picked {
                    if let firstUpdated = model.lines.first(where: { $0.displayName == flash.title }) {
                        withAnimation(.spring) {
                            proxy.scrollTo(firstUpdated.moveId, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Scanner

    private var scanner: some View {
        ZStack(alignment: .top) {
            BarcodeScannerView(
                mode: .continuous(debounce: .milliseconds(1500)),
                onScan: { code in model.handleScan(code) },
                onError: { message in model.error = message }
            )
            .frame(height: 280)
            .clipShape(.rect(cornerRadius: Radius.hero))
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
            .overlay(alignment: .bottom) {
                Text("Barcode scannen oder Zeile antippen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: .capsule)
                    .padding(.bottom, Spacing.xxl)
            }

            if let flash = model.lastScanFlash {
                ScanFlashBanner(flash: flash)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: flash.id) {
                        try? await Task.sleep(for: .milliseconds(1600))
                        if !Task.isCancelled, model.lastScanFlash?.id == flash.id {
                            withAnimation(.snappy) { model.clearFlash() }
                        }
                    }
            }
        }
        .frame(height: 280)
    }

    // MARK: - Helpers

    private var carrierToolbarLabel: String {
        if carrierWasChanged {
            return selectedCarrier?.name ?? "Kein Versender"
        }
        if let c = selectedCarrier { return c.name }
        if let c = model.currentCarrier, !c.isEmpty { return c.name }
        return "Versender"
    }

    private func preselectCarrier() {
        if let current = model.currentCarrier, !current.isEmpty {
            selectedCarrier = model.availableCarriers.first { $0.id == current.id }
        }
        carrierWasChanged = false
    }

    private func commit() async {
        let result = await model.commit(
            using: auth.client,
            selectedCarrier: selectedCarrier,
            carrierWasChanged: carrierWasChanged
        )
        switch result {
        case .completed(let message):
            commitMessage = message
        case .requiresBackorder:
            showingBackorderSheet = true
        case nil:
            break
        }
    }

    private func formatted(_ value: Double) -> String { value.qtyFormatted }
}

// MARK: - Row

private struct PickLineRow: View {
    let line: PickableLine
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.md) {
                statusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let code = line.defaultCode {
                            Label(code, systemImage: "number")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if let bc = line.barcode {
                            Label(bc, systemImage: "barcode")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    ProgressView(value: line.progress)
                        .tint(line.isComplete ? Theme.success : Theme.brand)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(formatted(line.picked)) / \(formatted(line.demand))")
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText(value: line.picked))
                    Text(line.uomName)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                line.isComplete ? Theme.success.opacity(0.10) : Color.clear,
                in: .rect(cornerRadius: Radius.standard)
            )
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.standard))
        }
        .buttonStyle(.plain)
    }

    private var statusIcon: some View {
        Image(systemName: line.isComplete ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(line.isComplete ? Theme.success : Theme.slate)
            .font(.title3)
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy, value: line.isComplete)
    }

    private func formatted(_ value: Double) -> String { value.qtyFormatted }
}

// MARK: - Scan flash

private struct ScanFlashBanner: View {
    let flash: OrderPickingViewModel.ScanFlash

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon).font(.title3.weight(.bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(flash.title).font(.subheadline.weight(.semibold))
                Text(flash.subtitle).font(.caption).opacity(0.8).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(tint, in: .rect(cornerRadius: Radius.standard))
        .foregroundStyle(.white)
        .shadow(color: tint.opacity(0.45), radius: 12, x: 0, y: 6)
    }

    private var tint: Color {
        switch flash.kind {
        case .picked:        return Theme.success
        case .alreadyDone:   return Theme.slate
        case .notInOrder:    return Theme.danger
        case .lookupFailed:  return Theme.warning
        }
    }

    private var icon: String {
        switch flash.kind {
        case .picked:        return "checkmark.circle.fill"
        case .alreadyDone:   return "checkmark.seal"
        case .notInOrder:    return "xmark.octagon.fill"
        case .lookupFailed:  return "questionmark.circle.fill"
        }
    }
}

// MARK: - Manual quantity sheet

private struct ManualQuantitySheet: View {
    let line: PickableLine
    @Binding var text: String
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Bedarf",
                                   value: "\(String(format: "%.0f", line.demand)) \(line.uomName)")
                    LabeledContent("Aktuell",
                                   value: String(format: "%.0f", line.picked))
                }
                Section("Neue Menge") {
                    TextField("Menge", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold().monospacedDigit())
                }
            }
            .navigationTitle(line.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        let normalized = text.replacingOccurrences(of: ",", with: ".")
                        if let qty = Double(normalized) {
                            onSave(qty)
                        }
                    }
                }
            }
        }
    }
}
