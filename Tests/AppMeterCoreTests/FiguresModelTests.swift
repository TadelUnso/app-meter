import Foundation
import Testing
@testable import AppMeterCore

@Suite("Figures grouping")
struct FiguresModelTests {
    private static func app(_ name: String, _ store: Store, id: String, lifetime: Int = 1, today: Int = 0) -> AppFigures {
        AppFigures(
            id: id,
            name: name,
            store: store,
            lifetime: lifetime,
            today: today,
            asOf: Date(timeIntervalSince1970: 0)
        )
    }

    /// The bundle id and the package are the same string for the same app, and
    /// that is what puts both stores in one row.
    @Test func oneAppOnBothStoresIsOneRow() {
        let rows = FiguresModel.rows([
            .appStore: [Self.app("Finder", .appStore, id: "com.example.finder", lifetime: 10, today: 2)],
            .googlePlay: [Self.app("com.example.finder", .googlePlay, id: "com.example.finder", lifetime: 5, today: 1)],
        ])

        #expect(rows.count == 1)
        #expect(rows[0].name == "Finder")
        #expect(rows[0].lifetime == 15)
        #expect(rows[0].today == 3)
    }

    /// Different identifiers are different apps, however alike the names look.
    @Test func differentIdentifiersStayApart() {
        let rows = FiguresModel.rows([
            .appStore: [Self.app("Finder", .appStore, id: "com.example.finder")],
            .googlePlay: [Self.app("Finder", .googlePlay, id: "com.other.finder")],
        ])
        #expect(rows.count == 2)
    }

    /// The App Store name is the human one; a Play-only row has nothing better
    /// than its package to show.
    @Test func theNameComesFromTheAppStoreWhenThereIsOne() {
        let rows = FiguresModel.rows([
            .googlePlay: [Self.app("com.example.app", .googlePlay, id: "com.example.app")],
        ])
        #expect(rows[0].name == "com.example.app")
    }

    /// Case must not scatter the sort: "app one" and "App Two" are neighbours.
    @Test func sortsByNameWithoutRegardToCase() {
        let rows = FiguresModel.rows([
            .appStore: [
                Self.app("App Two", .appStore, id: "two"),
                Self.app("app one", .appStore, id: "one"),
            ],
        ])
        #expect(rows.map(\.name) == ["app one", "App Two"])
    }

    @Test func emptyStoresGroupToNothing() {
        #expect(FiguresModel.rows([:]).isEmpty)
    }

    /// Two apps can share a name. Without a tiebreaker their order comes out of
    /// a hash and changes between launches, so the panel reshuffles itself for
    /// no reason the user can see.
    @Test func rowsWithTheSameNameAreOrderedByIdentifier() {
        let rows = FiguresModel.rows([
            .appStore: [
                Self.app("Finder", .appStore, id: "com.zebra.finder"),
                Self.app("Finder", .appStore, id: "com.acme.finder"),
            ],
        ])
        #expect(rows.map(\.id) == ["com.acme.finder", "com.zebra.finder"])
    }
}
