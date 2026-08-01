import Foundation

/// Where AppleInstallsService fetches what it needs from App Store Connect:
/// sales reports (cached and summed into figures) and app metadata (bundle ids,
/// used to pair apps across stores). Lives behind a protocol so the service can
/// be tested without a network.
public protocol SalesReportSource: Sendable {
    func report(for period: SalesPeriod) async throws -> SalesReport?
    /// Apple identifier → app. Empty when the key cannot list apps; the service
    /// then falls back to the identifiers and titles the reports carry.
    func apps() async throws -> [String: AppStoreApp]
}

extension AppStoreConnectClient: SalesReportSource {}

/// The App Store side of a refresh: the figures, and anything that went wrong
/// which was not bad enough to lose them.
public struct AppleInstalls: Sendable {
    public let figures: [AppFigures]
    /// Everything that went wrong along the way but was not bad enough to lose
    /// the figures over — a refused app listing, a rate limit that cut the walk
    /// short. A refresh can have more than one such thing, so a single optional
    /// string cannot say so.
    public let problems: [String]
    /// False when the walk stopped before covering the whole plan — today, only
    /// a rate limit does that. The caller needs this as a plain flag rather than
    /// having to recognise the rate-limit sentence inside `problems`.
    public let isComplete: Bool

    public init(figures: [AppFigures], problems: [String] = [], isComplete: Bool = true) {
        self.figures = figures
        self.problems = problems
        self.isComplete = isComplete
    }
}

/// Turns App Store Connect reports into the figures the panel shows.
///
/// The lifetime total is the sum of the whole plan; the day's growth is the
/// most recent daily report that had anything in it. Both come out of the same
/// pass, because the daily reports at the end of the plan are fetched anyway.
///
/// Requests go one at a time. After the first run almost all of them are served
/// from the cache, and a burst of forty parallel requests would be a good way
/// to meet Apple's rate limiter for no gain.
public struct AppleInstallsService: Sendable {
    private let client: any SalesReportSource
    private let history: InstallHistoryStore

    public init(client: any SalesReportSource, history: InstallHistoryStore = InstallHistoryStore()) {
        self.client = client
        self.history = history
    }

    public func installs(now: Date = Date()) async throws -> AppleInstalls {
        var totals: [String: Int] = [:]
        var titles = await history.current.titles
        var latestDay: (date: Date, units: [String: Int])?
        var problems: [String] = []
        var isComplete = true

        // A queue rather than a plain loop: a coarse period Apple has not
        // published yet is replaced here by the finer ones covering the same
        // stretch, and those join the same pass.
        var queue = SalesPeriods.lifetimePlan(upTo: now)
        var position = 0

        while position < queue.count {
            let period = queue[position]
            position += 1

            let closed = SalesPeriods.isClosed(period, on: now)
            var units: [String: Int]

            if closed, let cached = await history.units(for: period) {
                units = cached
            } else {
                // Nil is Apple's 404, which means either "nothing happened" or
                // "not published yet" and never says which. Caching it as zero
                // would seal a month that is merely late at nothing forever, so
                // it is not cached — the finer reports are asked instead.
                let report: SalesReport?
                do {
                    report = try await client.report(for: period)
                } catch AppStoreConnectError.rateLimited {
                    // Everything counted so far is real and already cached. Stopping here and
                    // showing an incomplete total beats showing nothing: the next refresh picks
                    // up from the cache and gets further.
                    problems.append("App Store: Apple is rate-limiting this key, so the total is still filling in.")
                    isComplete = false
                    break
                }
                guard let report else {
                    // Only a day's absence is ever cached. A day's report is published
                    // within about a day, so a settled day's 404 is trustworthy — it
                    // genuinely had nothing. A month or a year is a bigger aggregation
                    // that can take longer to publish, and guessing wrong there is not
                    // a wasted request but a real period's figures frozen at zero
                    // forever, so those always fall through to the finer periods
                    // instead; the fallback bottoms out at the days either way, and
                    // those are the ones this remembers.
                    if case .daily = period, SalesPeriods.isSettled(period, on: now) {
                        await history.store([:], titles: [:], for: period)
                    } else {
                        queue.append(contentsOf: SalesPeriods.finerPeriods(of: period, upTo: now))
                    }
                    continue
                }

                let downloads = report.firstDownloads()
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
            // the newest news there is. Compared by date rather than taken as
            // the last one seen, because a fallback appends older days after
            // newer ones.
            if case let .daily(year, month, day) = period, !units.isEmpty,
               let date = SalesPeriods.calendar.date(from: DateComponents(year: year, month: month, day: day)),
               date > (latestDay?.date ?? .distantPast) {
                latestDay = (date, units)
            }
        }

        var known: [String: AppStoreApp] = [:]
        do {
            known = try await client.apps()
        } catch {
            // Not fatal: the figures below are complete without it. But a key that is
            // refused this call is refused it on every refresh, so staying quiet would
            // leave the panel showing package ids forever with no reason given.
            problems.append("App Store: could not list apps — \(error.localizedDescription)")
        }

        // An app re-created under a new Apple identifier keeps its bundle id,
        // so both identifiers turn up in the history and must be combined.
        var byID: [String: AppFigures] = [:]
        for identifier in totals.keys.sorted() {
            let app = known[identifier]
            let id = app?.bundleID ?? identifier
            let name = app?.name ?? titles[identifier] ?? identifier
            let lifetime = totals[identifier] ?? 0
            let today = latestDay?.units[identifier] ?? 0
            // No fallback to `now`: a day this fresh has not necessarily been
            // published yet, and the freshness tile exists to say which day the
            // figures are really from — making one up would defeat the point.
            let asOf = latestDay?.date

            if let existing = byID[id] {
                // Same bundle id from a different Apple identifier: combine them.
                byID[id] = AppFigures(
                    id: id,
                    name: existing.name.isEmpty ? name : existing.name,
                    store: .appStore,
                    lifetime: existing.lifetime + lifetime,
                    today: existing.today + today,
                    asOf: [existing.asOf, asOf].compactMap { $0 }.max()
                )
            } else {
                byID[id] = AppFigures(
                    id: id,
                    name: name,
                    store: .appStore,
                    lifetime: lifetime,
                    today: today,
                    asOf: asOf
                )
            }
        }

        let figures = byID.keys.sorted().map { byID[$0]! }
        return AppleInstalls(figures: figures, problems: problems, isComplete: isComplete)
    }
}
