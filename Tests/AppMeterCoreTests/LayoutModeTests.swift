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
}
