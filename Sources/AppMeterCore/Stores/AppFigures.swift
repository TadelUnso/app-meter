import Foundation

/// Which store a figure came from.
public enum Store: String, Equatable, Sendable, CaseIterable {
    case appStore
    case googlePlay
}

/// One app's numbers on one store: the lifetime total, and how much of it
/// arrived on the most recent day the store has reported.
///
/// Deliberately not optional-per-field: an app either has figures for a store or
/// has no entry for it at all. A half-filled row would have to be rendered as
/// something, and every choice there reads as a real number.
public struct AppFigures: Equatable, Sendable, Identifiable {
    /// Bundle id on Apple, package name on Google. Stable across renames, which
    /// the display name is not.
    public let id: String
    public let name: String
    public let store: Store
    public let lifetime: Int
    public let today: Int

    /// The day `today` covers. Both stores report a day or more behind, so this
    /// is not necessarily today's date, and the panel says which day it means.
    public let asOf: Date

    public init(id: String, name: String, store: Store, lifetime: Int, today: Int, asOf: Date) {
        self.id = id
        self.name = name
        self.store = store
        self.lifetime = lifetime
        self.today = today
        self.asOf = asOf
    }
}
