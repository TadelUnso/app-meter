import Foundation
import Testing
@testable import AppMeterCore

@Suite("Figures merging")
struct FiguresModelTests {
    private static func app(_ name: String, _ store: Store, id: String? = nil) -> AppFigures {
        AppFigures(
            id: id ?? "\(name)-\(store.rawValue)",
            name: name,
            store: store,
            lifetime: 1,
            today: 0,
            asOf: Date(timeIntervalSince1970: 0)
        )
    }

    /// The same app on both stores must sit together, App Store first — that
    /// adjacency is what makes the store dots readable as a pair.
    @Test func groupsTheSameAppAcrossStores() {
        let merged = FiguresModel.merged([
            .appStore: [Self.app("Finder", .appStore)],
            .googlePlay: [Self.app("Finder", .googlePlay), Self.app("Another", .googlePlay)],
        ])

        #expect(merged.map(\.name) == ["Another", "Finder", "Finder"])
        #expect(merged[1].store == .appStore)
        #expect(merged[2].store == .googlePlay)
    }

    /// Case must not scatter the sort: "app one" and "App Two" are neighbours.
    @Test func sortsWithoutRegardToCase() {
        let merged = FiguresModel.merged([
            .appStore: [Self.app("app one", .appStore), Self.app("App Two", .appStore)],
        ])
        #expect(merged.map(\.name) == ["app one", "App Two"])
    }

    @Test func emptyStoresMergeToNothing() {
        #expect(FiguresModel.merged([:]).isEmpty)
    }
}
