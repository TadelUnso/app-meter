import Foundation
import Testing
@testable import AppMeterCore

@Suite("Fmt")
struct FmtTests {
    private static let sep = Fmt.groupSeparator

    @Test("groups thousands", arguments: [
        (0, "0"),
        (7, "7"),
        (999, "999"),
        (1000, "1\(sep)000"),
        (1284, "1\(sep)284"),
        (214_900, "214\(sep)900"),
        (1_000_000, "1\(sep)000\(sep)000"),
    ])
    func installs(value: Int, expected: String) {
        #expect(Fmt.installs(value) == expected)
    }

    @Test("signs the daily change", arguments: [
        (1284, "+1\(sep)284"),
        (437, "+437"),
        (0, "—"),
        (-12, "-12"),
        (-1284, "-1\(sep)284"),
    ])
    func delta(value: Int, expected: String) {
        #expect(Fmt.delta(value) == expected)
    }

    /// Grouping is built from the magnitude precisely so this does not overflow.
    @Test func intMinDoesNotTrap() {
        #expect(Fmt.installs(Int.min).hasPrefix("-9"))
    }

    /// The separator has to be the narrow no-break space, not a plain space:
    /// a plain space lets a line break fall inside a number.
    @Test func separatorIsNonBreaking() {
        #expect(Fmt.groupSeparator == "\u{202F}")
    }

    /// Day and month, no year: the panel never shows a date more than a week old.
    @Test func daysAreWrittenShort() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 30
        let date = SalesPeriods.calendar.date(from: components)!
        #expect(Fmt.day(date) == "30 Jul")
    }

    /// How long ago the stores were asked, in the shortest form that is still
    /// unambiguous. Minutes for the first hour, then hours.
    @Test func agesReadAsRoundedUnits() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        #expect(Fmt.age(now.addingTimeInterval(-20), now: now) == "just now")
        #expect(Fmt.age(now.addingTimeInterval(-60), now: now) == "1 min ago")
        #expect(Fmt.age(now.addingTimeInterval(-25 * 60), now: now) == "25 min ago")
        #expect(Fmt.age(now.addingTimeInterval(-60 * 60), now: now) == "1 h ago")
        #expect(Fmt.age(now.addingTimeInterval(-5 * 60 * 60), now: now) == "5 h ago")
    }

    /// A clock that jumped backwards must not print a negative age.
    @Test func aFutureRefreshReadsAsJustNow() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        #expect(Fmt.age(now.addingTimeInterval(120), now: now) == "just now")
    }
}
