import Foundation

extension Double {
    /// Compact quantity rendering for warehouse / stock UI: integer
    /// when the value has no fractional part, two-digit fractional
    /// otherwise. Replaces a `private func formatted(_:)` that was
    /// duplicated across four picking / inventory views.
    var qtyFormatted: String {
        let rounded = (self * 100).rounded() / 100
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rounded)
        } else {
            return String(format: "%.2f", rounded)
        }
    }
}
