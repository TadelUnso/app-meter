import Foundation
import Testing
@testable import AppMeterCore

@Suite("LayoutMode")
struct LayoutModeTests {
    @Test("picks a mode for every count", arguments: [
        (0, LayoutMode.empty),
        (1, .single),
        (2, .grid),
        (3, .grid),
        (4, .grid),
        (5, .rows),
        (50, .rows),
    ])
    func mode(count: Int, expected: LayoutMode) {
        #expect(LayoutMode.mode(for: count) == expected)
    }

    /// A negative count cannot arrive from the config store, but the switch has
    /// to be total and the empty panel is the only sane answer.
    @Test func negativeCountIsEmpty() {
        #expect(LayoutMode.mode(for: -1) == .empty)
    }

    @Test func chunksSplitsEvenly() {
        #expect([1, 2, 3, 4].chunks(of: 2) == [[1, 2], [3, 4]])
    }

    @Test func chunksLeavesLastGroupShort() {
        #expect([1, 2, 3].chunks(of: 2) == [[1, 2], [3]])
    }

    @Test func chunksOfEmptyIsEmpty() {
        #expect([Int]().chunks(of: 2).isEmpty)
    }

    /// Guards the division: a zero size would otherwise make `stride` trap.
    @Test func chunksOfZeroIsEmpty() {
        #expect([1, 2, 3].chunks(of: 0).isEmpty)
    }

    /// The panel at its narrowest, measured: 350 pt less 14 pt of padding a
    /// side leaves 322 pt of row, and the capsule takes 111 pt out of the
    /// middle of it. That leaves 105.5 pt either side, less the 6 pt gap.
    @Test func titleLimitLeavesRoomBeforeTheCapsule() {
        #expect(LayoutMode.titleLimit(content: 322, kofi: 111, gap: 6) == 99.5)
    }

    /// Before the capsule has reported a width there is nothing to avoid, and
    /// a limit of zero would collapse the title for a frame.
    @Test func titleLimitIsUnboundedUntilTheCapsuleReports() {
        #expect(LayoutMode.titleLimit(content: 322, kofi: 0, gap: 6) == .infinity)
    }

    /// A capsule wider than the row it sits in leaves the title no room at
    /// all — but never a negative frame, which SwiftUI would trap on.
    @Test func titleLimitNeverGoesNegative() {
        #expect(LayoutMode.titleLimit(content: 100, kofi: 200, gap: 6) == 0)
    }

    private static func row(_ name: String) -> AppRow {
        AppRow(id: name, name: name, appStore: nil, googlePlay: nil)
    }

    private static func figures(store: Store, lifetime: Int, today: Int) -> AppFigures {
        AppFigures(
            id: "id",
            name: "name",
            store: store,
            lifetime: lifetime,
            today: today,
            asOf: Date(timeIntervalSince1970: 0)
        )
    }

    /// One app puts its own name in the title bar; anything else is the app's own
    /// name, which would be a lie about which figures are on screen.
    @Test func theTitleIsTheAppNameOnlyWhenThereIsOneApp() {
        #expect(LayoutMode.title(for: []) == "App Meter")
        #expect(LayoutMode.title(for: [Self.row("Бюро Знахідок")]) == "Бюро Знахідок")
        #expect(LayoutMode.title(for: [Self.row("One"), Self.row("Two")]) == "App Meter")
    }

    /// Adding two stores of one app is a real number. Adding up different apps is
    /// not, so the summary exists only for the single-app panel.
    @Test func theCombinedTotalIsOnlyForOneAppOnBothStores() {
        let both = AppRow(
            id: "com.example.app",
            name: "Finder",
            appStore: Self.figures(store: .appStore, lifetime: 15, today: 1),
            googlePlay: Self.figures(store: .googlePlay, lifetime: 9, today: 0)
        )
        #expect(LayoutMode.combinedTotal(for: [both]) == "24 together")

        let oneStore = AppRow(id: "a", name: "A", appStore: both.appStore, googlePlay: nil)
        #expect(LayoutMode.combinedTotal(for: [oneStore]) == nil)
        #expect(LayoutMode.combinedTotal(for: [both, both]) == nil)
        #expect(LayoutMode.combinedTotal(for: []) == nil)
    }
}
