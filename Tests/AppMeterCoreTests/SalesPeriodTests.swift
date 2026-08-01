import Foundation
import Testing
@testable import AppMeterCore

@Suite("Sales periods")
struct SalesPeriodTests {
    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private static let midJuly = date("2026-07-30T12:00:00Z")

    @Test func reportDateMatchesWhatEachFrequencyExpects() {
        #expect(SalesPeriod.yearly(2025).reportDate == "2025")
        #expect(SalesPeriod.monthly(year: 2026, month: 3).reportDate == "2026-03")
        #expect(SalesPeriod.daily(year: 2026, month: 7, day: 5).reportDate == "2026-07-05")
    }

    @Test func frequencyMatchesTheCase() {
        #expect(SalesPeriod.yearly(2025).frequency == .yearly)
        #expect(SalesPeriod.monthly(year: 2026, month: 3).frequency == .monthly)
        #expect(SalesPeriod.daily(year: 2026, month: 7, day: 5).frequency == .daily)
    }

    /// The plan's whole reason to exist: 3 years + 6 months + 30 days is 39
    /// requests where a day-by-day walk over the same stretch would be over a
    /// thousand.
    @Test func planCoversTheStretchWithoutOverlap() {
        let plan = SalesPeriods.lifetimePlan(upTo: Self.midJuly)

        #expect(plan.prefix(3) == [.yearly(2023), .yearly(2024), .yearly(2025)])
        #expect(plan.dropFirst(3).prefix(6) == [
            .monthly(year: 2026, month: 1),
            .monthly(year: 2026, month: 2),
            .monthly(year: 2026, month: 3),
            .monthly(year: 2026, month: 4),
            .monthly(year: 2026, month: 5),
            .monthly(year: 2026, month: 6),
        ])
        #expect(plan.suffix(2) == [
            .daily(year: 2026, month: 7, day: 29),
            .daily(year: 2026, month: 7, day: 30),
        ])
        #expect(plan.count == 3 + 6 + 30)
    }

    /// Every period appears once — the property that makes summing the plan a
    /// lifetime total rather than an inflated one.
    @Test func planHasNoDuplicates() {
        let plan = SalesPeriods.lifetimePlan(upTo: Self.midJuly)
        #expect(Set(plan).count == plan.count)
    }

    /// On the first of January the year has no closed months and the month has
    /// exactly one day — the shape most likely to be off by one.
    @Test func planOnNewYearsDayIsJustThatDay() {
        let plan = SalesPeriods.lifetimePlan(upTo: Self.date("2026-01-01T09:00:00Z"))
        #expect(plan == [
            .yearly(2023), .yearly(2024), .yearly(2025),
            .daily(year: 2026, month: 1, day: 1),
        ])
    }

    @Test func closedPeriodsAreTheOnesWhoseTimeIsOver() {
        #expect(SalesPeriods.isClosed(.yearly(2025), on: Self.midJuly))
        #expect(!SalesPeriods.isClosed(.yearly(2026), on: Self.midJuly))

        #expect(SalesPeriods.isClosed(.monthly(year: 2026, month: 6), on: Self.midJuly))
        #expect(!SalesPeriods.isClosed(.monthly(year: 2026, month: 7), on: Self.midJuly))

        #expect(SalesPeriods.isClosed(.daily(year: 2026, month: 7, day: 29), on: Self.midJuly))
    }

    /// Today's own report is still being written — caching it would freeze the
    /// day's growth at whatever it was on the first refresh.
    @Test func todayIsNotClosed() {
        #expect(!SalesPeriods.isClosed(.daily(year: 2026, month: 7, day: 30), on: Self.midJuly))
    }

    /// A month Apple has not summarised yet is covered by its days instead.
    @Test func aMonthBreaksDownIntoItsDays() {
        let days = SalesPeriods.finerPeriods(of: .monthly(year: 2026, month: 6), upTo: Self.midJuly)
        #expect(days.count == 30)
        #expect(days.first == .daily(year: 2026, month: 6, day: 1))
        #expect(days.last == .daily(year: 2026, month: 6, day: 30))
    }

    /// The month in progress stops at today: later days have no report at all.
    @Test func theCurrentMonthBreaksDownOnlyAsFarAsToday() {
        let days = SalesPeriods.finerPeriods(of: .monthly(year: 2026, month: 7), upTo: Self.midJuly)
        #expect(days.count == 30)
        #expect(days.last == .daily(year: 2026, month: 7, day: 30))
    }

    /// Same again a level up, for the first days of January.
    @Test func aYearBreaksDownIntoItsMonths() {
        #expect(SalesPeriods.finerPeriods(of: .yearly(2025), upTo: Self.midJuly).count == 12)
        #expect(SalesPeriods.finerPeriods(of: .yearly(2026), upTo: Self.midJuly)
            == (1...7).map { .monthly(year: 2026, month: $0) })
    }

    /// A day is as fine as Apple's reports go.
    @Test func aDayBreaksDownNoFurther() {
        #expect(SalesPeriods.finerPeriods(of: .daily(year: 2026, month: 7, day: 5), upTo: Self.midJuly).isEmpty)
    }

    /// A period Apple has had ample time to publish. Past this point an absent
    /// report means the period was empty, not late.
    @Test func aLongClosedPeriodIsSettled() {
        #expect(SalesPeriods.isSettled(.yearly(2023), on: Self.midJuly))
        #expect(SalesPeriods.isSettled(.monthly(year: 2026, month: 5), on: Self.midJuly))
        #expect(SalesPeriods.isSettled(.daily(year: 2026, month: 7, day: 1), on: Self.midJuly))
    }

    /// The just-ended period is exactly the one Apple is still working on, and the
    /// one the fallback exists for.
    @Test func aRecentlyClosedPeriodIsNotSettled() {
        #expect(!SalesPeriods.isSettled(.monthly(year: 2026, month: 6), on: Self.date("2026-07-02T12:00:00Z")))
        #expect(!SalesPeriods.isSettled(.daily(year: 2026, month: 7, day: 29), on: Self.midJuly))
        #expect(!SalesPeriods.isSettled(.yearly(2025), on: Self.date("2026-01-03T12:00:00Z")))
    }

    /// An open period is never settled, however the arithmetic falls out.
    @Test func anOpenPeriodIsNeverSettled() {
        #expect(!SalesPeriods.isSettled(.yearly(2026), on: Self.midJuly))
        #expect(!SalesPeriods.isSettled(.monthly(year: 2026, month: 7), on: Self.midJuly))
        #expect(!SalesPeriods.isSettled(.daily(year: 2026, month: 7, day: 30), on: Self.midJuly))
    }
}
