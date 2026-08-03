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

        let days = try await client.firstOpens(from: start, through: now)
        let today = Calendar.utc.startOfDay(for: now)

        return AppFigures(
            id: play.id,
            name: play.name,
            store: play.store,
            lifetime: play.lifetime + days.reduce(0) { $0 + $1.count },
            today: days.filter { Calendar.utc.isDate($0.date, inSameDayAs: today) }.reduce(0) { $0 + $1.count },
            asOf: today
        )
    }
}

private extension Calendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
