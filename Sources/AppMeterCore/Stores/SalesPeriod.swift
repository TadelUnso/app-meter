import Foundation

public enum SalesFrequency: String, Sendable {
    case daily = "DAILY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"
}

/// One report's worth of time.
///
/// Apple publishes the same sales at several granularities, and the lifetime
/// total is assembled from the coarsest ones that cover each stretch: a year is
/// one request where 365 days would be 365. The fine granularity is only needed
/// for the stretch a coarse report does not cover yet — the current month.
public enum SalesPeriod: Hashable, Sendable {
    case yearly(Int)
    case monthly(year: Int, month: Int)
    case daily(year: Int, month: Int, day: Int)

    public var frequency: SalesFrequency {
        switch self {
        case .yearly: .yearly
        case .monthly: .monthly
        case .daily: .daily
        }
    }

    /// What `filter[reportDate]` wants: a year, a year-month, or a full date.
    public var reportDate: String {
        switch self {
        case let .yearly(year):
            String(format: "%04d", year)
        case let .monthly(year, month):
            String(format: "%04d-%02d", year, month)
        case let .daily(year, month, day):
            String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    /// Doubles as the cache key. The frequency has to be part of it: 2026 the
    /// year and 2026 the… nothing else, but a bare date string would collide
    /// the day 2026-07-30 with nothing today and something once Apple adds a
    /// frequency. Cheap insurance, one character.
    public var cacheKey: String { "\(frequency.rawValue):\(reportDate)" }
}

public enum SalesPeriods {
    /// UTC throughout, matching the format Apple's report dates are written in.
    /// A calendar in the user's own zone would roll the day over at a different
    /// moment than Apple does and ask for a day that has no report yet.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// How far back to look for yearly reports.
    ///
    /// Apple does not keep sales history forever, and asking for 2012 costs a
    /// request to be told so. Three full years back is past the retention of
    /// every frequency, so nothing further could be answered anyway.
    public static let yearsOfHistory = 3

    /// The periods whose sum is the lifetime total, coarsest first.
    ///
    /// Every stretch of time is covered exactly once: whole years before this
    /// one, whole months before this month, then the days of this month up to
    /// and including `today`. No overlap, so summing cannot double-count.
    public static func lifetimePlan(upTo today: Date, yearsBack: Int = yearsOfHistory) -> [SalesPeriod] {
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return [] }

        var periods: [SalesPeriod] = []
        for past in (year - yearsBack)..<year {
            periods.append(.yearly(past))
        }
        for past in 1..<month {
            periods.append(.monthly(year: year, month: past))
        }
        for past in 1...day {
            periods.append(.daily(year: year, month: month, day: past))
        }
        return periods
    }

    /// The same stretch of time one step finer: a year is its months, a month
    /// its days, a day nothing.
    ///
    /// This is the answer to a coarse report Apple has not published yet. The
    /// monthly summary of a month arrives some days into the next one, and the
    /// yearly summary of a year some days into the next — until then the finer
    /// reports are the only ones that cover that stretch. Nothing past `today`,
    /// which has no report of any frequency.
    public static func finerPeriods(of period: SalesPeriod, upTo today: Date) -> [SalesPeriod] {
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let thisYear = parts.year, let thisMonth = parts.month, let thisDay = parts.day else { return [] }

        switch period {
        case let .yearly(year):
            guard year <= thisYear else { return [] }
            let lastMonth = year == thisYear ? thisMonth : 12
            return (1...lastMonth).map { .monthly(year: year, month: $0) }

        case let .monthly(year, month):
            guard year < thisYear || (year == thisYear && month <= thisMonth) else { return [] }
            let lastDay: Int
            if year == thisYear, month == thisMonth {
                lastDay = thisDay
            } else {
                guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                      let range = calendar.range(of: .day, in: .month, for: first)
                else { return [] }
                lastDay = range.count
            }
            return (1...lastDay).map { .daily(year: year, month: month, day: $0) }

        case .daily:
            return []
        }
    }

    /// A period is closed once the time it covers is over — and a closed
    /// period's figures never change again, which is what makes them safe to
    /// cache forever. The current day, month and year stay open.
    public static func isClosed(_ period: SalesPeriod, on today: Date) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return false }

        switch period {
        case let .yearly(reportYear):
            return reportYear < year
        case let .monthly(reportYear, reportMonth):
            return reportYear < year || (reportYear == year && reportMonth < month)
        case let .daily(reportYear, reportMonth, reportDay):
            return reportYear < year
                || (reportYear == year && reportMonth < month)
                || (reportYear == year && reportMonth == month && reportDay < day)
        }
    }

    /// How long after a day ends Apple may still be publishing its report.
    ///
    /// Deliberately sized for a day, not a coarser period: a day's report is
    /// published within about a day, so three days of margin is a safe bet, not
    /// a guess. The same guess for a month or a year would be a real gamble —
    /// an unsettled month re-expands into up to 31 requests every refresh, an
    /// unsettled year into twelve months plus their days, and guessing wrong
    /// there does not cost "one wasted request." It caches a real period's
    /// figures as zero, permanently: nothing ever re-checks or expires a stored
    /// period, so a wrong guess is silent, unrecoverable data loss. That is why
    /// only a day's absence is ever cached — see the call site.
    public static let dailyPublicationLag: TimeInterval = 3 * 24 * 60 * 60

    /// Whether a period is old enough that a missing report means an empty period
    /// rather than a late one.
    ///
    /// Measured against `dailyPublicationLag`, so this is only trustworthy at
    /// the granularity that constant was sized for: a day. Callers must not use
    /// it to decide whether a month's or a year's absence is safe to cache — a
    /// coarser report can legitimately still be missing well past three days.
    public static func isSettled(_ period: SalesPeriod, on today: Date) -> Bool {
        guard isClosed(period, on: today), let end = endOfPeriod(period) else { return false }
        return today.timeIntervalSince(end) > dailyPublicationLag
    }

    /// The first instant after the period's last day.
    private static func endOfPeriod(_ period: SalesPeriod) -> Date? {
        var components = DateComponents()
        switch period {
        case let .yearly(year):
            components.year = year + 1
            components.month = 1
            components.day = 1
        case let .monthly(year, month):
            components.year = month == 12 ? year + 1 : year
            components.month = month == 12 ? 1 : month + 1
            components.day = 1
        case let .daily(year, month, day):
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                return nil
            }
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        return calendar.date(from: components)
    }
}
