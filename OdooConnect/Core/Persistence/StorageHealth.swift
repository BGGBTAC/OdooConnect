import Foundation
import Observation

/// Observable signal that the persistent SwiftData store could not be opened
/// and the app is running on a volatile in-memory fallback. Surfaced as a
/// persistent banner (see `RootView`) so the user knows locally created
/// drafts will be lost when the app is terminated, instead of the failure
/// being swallowed silently.
@Observable
@MainActor
final class StorageHealth {
    var isDegraded: Bool
    var degradedReason: String?

    init(isDegraded: Bool = false, degradedReason: String? = nil) {
        self.isDegraded = isDegraded
        self.degradedReason = degradedReason
    }
}
