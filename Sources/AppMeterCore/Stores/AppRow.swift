import Foundation

/// An app as the user thinks of it: one identity, up to two stores.
///
/// The identity is the bundle id, which Play calls the package name — the one
/// field both stores publish for the same app. An app whose two stores disagree
/// about it is two rows, which is the honest answer rather than a guess.
public struct AppRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let appStore: AppFigures?
    public let googlePlay: AppFigures?

    public init(id: String, name: String, appStore: AppFigures?, googlePlay: AppFigures?) {
        self.id = id
        self.name = name
        self.appStore = appStore
        self.googlePlay = googlePlay
    }

    /// Both stores together. Only the single-app layout shows this — summing
    /// across different apps would be a number with no meaning.
    public var lifetime: Int { (appStore?.lifetime ?? 0) + (googlePlay?.lifetime ?? 0) }
}
