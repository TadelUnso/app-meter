import Foundation

/// Turns App Store Connect reports into the figures the panel shows.
///
/// The lifetime total is the sum of the whole plan; the day's growth is the
/// most recent daily report that had anything in it. Both come out of the same
/// pass, because the daily reports at the end of the plan are fetched anyway.
///
/// Requests go one at a time. After the first run almost all of them are served
/// from the cache, and a burst of forty parallel requests would be a good way
/// to meet Apple's rate limiter for no gain.
/// Where a period's report comes from. The one implementation that matters is
/// `AppStoreConnectClient`; the protocol exists so the caching and summing
/// below can be tested without a network.
public protocol SalesReportSource: Sendable {
    func report(for period: SalesPeriod) async throws -> SalesReport?
}

extension AppStoreConnectClient: SalesReportSource {}

public struct AppleInstallsService: Sendable {
    private let client: any SalesReportSource
    private let history: InstallHistoryStore

    public init(client: any SalesReportSource, history: InstallHistoryStore = InstallHistoryStore()) {
        self.client = client
        self.history = history
    }

    public func figures(now: Date = Date()) async throws -> [AppFigures] {
        var totals: [String: Int] = [:]
        var titles = await history.current.titles
        var latestDay: (date: Date, units: [String: Int])?

        for period in SalesPeriods.lifetimePlan(upTo: now) {
            let closed = SalesPeriods.isClosed(period, on: now)
            var units: [String: Int]

            if closed, let cached = await history.units(for: period) {
                units = cached
            } else {
                let downloads = try await client.report(for: period)?.firstDownloads() ?? [:]
                units = downloads.mapValues(\.units)

                let names = downloads.mapValues(\.title)
                titles.merge(names) { _, latest in latest }

                if closed {
                    await history.store(units, titles: names, for: period)
                } else {
                    await history.remember(titles: names)
                }
            }

            for (identifier, count) in units {
                totals[identifier, default: 0] += count
            }

            // The newest daily report that had downloads in it is what "today"
            // means here: Apple publishes a day or so behind, so that report is
            // the newest news there is.
            if case let .daily(year, month, day) = period, !units.isEmpty,
               let date = SalesPeriods.calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                latestDay = (date, units)
            }
        }

        return totals.keys.sorted().map { identifier in
            AppFigures(
                id: identifier,
                name: titles[identifier] ?? identifier,
                store: .appStore,
                lifetime: totals[identifier] ?? 0,
                today: latestDay?.units[identifier] ?? 0,
                asOf: latestDay?.date ?? now
            )
        }
    }
}
