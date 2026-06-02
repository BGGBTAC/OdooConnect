import SwiftUI

/// `.alert(_, isPresented: .constant(error != nil))` was used in 13
/// places. The `.constant` binding's setter is a no-op, which means
/// when SwiftUI itself tries to dismiss the alert (e.g. the user
/// swipes it away on iPad, or accessibility actions), the source
/// `String?` stays non-nil and the alert immediately reopens.
///
/// These modifiers replace that pattern with a real two-way binding
/// that resets the source on dismiss, while keeping the per-callsite
/// usage just as terse.
extension View {
    /// Renders an OK-only error alert bound to a `String?` source.
    /// Tapping OK or any system-driven dismiss clears the source.
    func errorAlert(
        _ title: LocalizedStringKey = "Fehler",
        error: Binding<String?>
    ) -> some View {
        modifier(SourceAlertModifier(
            title: title,
            buttonLabel: "OK",
            source: error,
            isDestructive: false
        ))
    }

    /// Same shape as `errorAlert` but with neutral framing — for
    /// "Hinweis"-style confirmations that aren't errors.
    func infoAlert(
        _ title: LocalizedStringKey = "Hinweis",
        message: Binding<String?>
    ) -> some View {
        modifier(SourceAlertModifier(
            title: title,
            buttonLabel: "OK",
            source: message,
            isDestructive: false
        ))
    }

    /// A destructive confirmation dialog bound to a `Bool` source. Mirrors
    /// the terseness of `errorAlert`/`infoAlert`. `action` runs only when the
    /// user taps the destructive button; an explicit Cancel is provided.
    func destructiveConfirm(
        _ title: LocalizedStringKey,
        isPresented: Binding<Bool>,
        confirmLabel: LocalizedStringKey,
        message: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(confirmLabel, role: .destructive, action: action)
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text(message)
        }
    }
}

private struct SourceAlertModifier: ViewModifier {
    let title: LocalizedStringKey
    let buttonLabel: LocalizedStringKey
    @Binding var source: String?
    let isDestructive: Bool

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(
                get: { source != nil },
                set: { presented in if !presented { source = nil } }
            )
        ) {
            Button(buttonLabel, role: isDestructive ? .destructive : .cancel) {
                source = nil
            }
        } message: {
            Text(source ?? "")
        }
    }
}
