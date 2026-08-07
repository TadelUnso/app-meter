import Foundation

/// Extends a confirmed Play total with Firebase first opens that happened
/// after Play's newest report day. When Play catches up, those days leave the
/// query window, so the same install is never deliberately counted twice.
public struct GoogleAnalyticsInstallsService: Sendable {
    private let client: any GoogleAnalyticsFirstOpenSource

    public init(client: any GoogleAnalyticsFirstOpenSource) {
        self.client = client
    }

    public func supplement(_ play: AppFigures, now: Date = Date()) async throws -> AppFigures {
        guard play.store == .googlePlay,
              let asOf = play.asOf,
              let start = Calendar.utc.date(byAdding: .day, value: 1, to: asOf),
              start <= now
        else { return play }

        let report = try await client.firstOpens(since: start)
        let today = Self.day(of: now, in: report.timeZone)

        return AppFigures(
            id: play.id,
            name: play.name,
            store: play.store,
            lifetime: play.lifetime + report.days.reduce(0) { $0 + $1.count },
            // Both sides of this are UTC-anchored labels, so they compare
            // exactly; nothing here needs a same-day calendar comparison.
            today: report.days.filter { $0.date == today }.reduce(0) { $0 + $1.count },
            asOf: today
        )
    }

    /// Which day `now` falls on for a property keeping `zone`, expressed the way
    /// every day in this panel is expressed: midnight UTC of that calendar date.
    ///
    /// Reading the calendar date in the property's zone and re-anchoring it in
    /// UTC is the whole point. A property three hours ahead has begun a new day
    /// while UTC is still on the old one, and GA4 has already filed that day's
    /// events under tomorrow's label — so asking UTC what day it is would look
    /// for a label GA4 will not use for another three hours.
    /// Pure, hence testable without a network or a clock.
    static func day(of now: Date, in zone: TimeZone) -> Date {
        var property = Calendar(identifier: .gregorian)
        property.timeZone = zone
        let parts = property.dateComponents([.year, .month, .day], from: now)

        // Force-unwrapped: the components come from a real date, so they always
        // describe a day that exists.
        return Calendar.utc.date(
            from: DateComponents(year: parts.year, month: parts.month, day: parts.day)
        )!
    }
}

private extension Calendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
