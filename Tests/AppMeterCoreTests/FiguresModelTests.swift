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
    }

    /// Different identifiers are different apps, however alike the names look.
    @Test func differentIdentifiersStayApart() {
        let rows = FiguresModel.rows([
            .appStore: [Self.app("Finder", .appStore, id: "com.example.finder")],
            .googlePlay: [Self.app("Finder", .googlePlay, id: "com.other.finder")],
        ])
        #expect(rows.count == 2)
    }

    /// A Play-only row has nothing better than its package to show.
    @Test func aPlayOnlyRowFallsBackToItsPackageAsTheName() {
        let rows = FiguresModel.rows([
            .googlePlay: [Self.app("com.example.app", .googlePlay, id: "com.example.app")],
        ])
        #expect(rows[0].name == "com.example.app")
    }

    /// The App Store name is the human one, so it wins over Play's package
    /// name when both stores carry the same app.
    @Test func theNameComesFromTheAppStoreWhenBothStoresHaveTheApp() {
        let rows = FiguresModel.rows([
            .appStore: [Self.app("Finder", .appStore, id: "com.example.finder")],
            .googlePlay: [Self.app("com.example.finder", .googlePlay, id: "com.example.finder")],
        ])
        #expect(rows[0].name == "Finder")
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

    /// The bug this guards against: a rate limit cutting the walk short must
    /// not let a small partial total overwrite a complete one already on screen.
    @Test func anIncompleteResultDoesNotReplaceRetainedFigures() {
        let existing = [Self.app("Finder", .appStore, id: "com.example.finder", lifetime: 15_200)]
        let incoming = AppleInstalls(
            figures: [Self.app("Finder", .appStore, id: "com.example.finder", lifetime: 480)],
            isComplete: false
        )

        let figures = FiguresModel.retainedAppleFigures(existing: existing, incoming: incoming)

        #expect(figures == existing)
    }

    /// A first run has no prior figures to protect, so the partial is shown
    /// rather than nothing.
    @Test func anIncompleteResultIsPublishedWhenThereIsNothingPrior() {
        let incoming = AppleInstalls(
            figures: [Self.app("Finder", .appStore, id: "com.example.finder", lifetime: 480)],
            isComplete: false
        )

        let figures = FiguresModel.retainedAppleFigures(existing: nil, incoming: incoming)

        #expect(figures == incoming.figures)
    }

    /// A complete result always replaces, even over its own prior figures.
    @Test func aCompleteResultReplacesWhatCameBefore() {
        let existing = [Self.app("Finder", .appStore, id: "com.example.finder", lifetime: 15_200)]
        let incoming = AppleInstalls(
            figures: [Self.app("Finder", .appStore, id: "com.example.finder", lifetime: 15_400)]
        )

        let figures = FiguresModel.retainedAppleFigures(existing: existing, incoming: incoming)

        #expect(figures == incoming.figures)
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
