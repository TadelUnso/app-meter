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

    private static func row(_ name: String) -> AppRow {
        AppRow(id: name, name: name, appStore: nil, googlePlay: nil)
    }

    /// One app puts its own name in the title bar; anything else is the app's own
    /// name, which would be a lie about which figures are on screen.
    @Test func theTitleIsTheAppNameOnlyWhenThereIsOneApp() {
        #expect(LayoutMode.title(for: []) == "App Meter")
        #expect(LayoutMode.title(for: [Self.row("Бюро Знахідок")]) == "Бюро Знахідок")
        #expect(LayoutMode.title(for: [Self.row("One"), Self.row("Two")]) == "App Meter")
    }
}
