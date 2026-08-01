import Foundation
import Testing
@testable import AppMeterCore

/// Answers with a fixed report per period and counts what was asked for, so a
/// test can tell a cache hit from a fetch.
private actor StubSource: SalesReportSource {
    private let reports: [String: SalesReport]
    private let knownApps: [String: AppStoreApp]
    private(set) var requested: [String] = []

    init(_ reports: [SalesPeriod: SalesReport], apps: [String: AppStoreApp] = [:]) {
        self.reports = Dictionary(uniqueKeysWithValues: reports.map { ($0.key.cacheKey, $0.value) })
        self.knownApps = apps
    }

    func report(for period: SalesPeriod) async throws -> SalesReport? {
        requested.append(period.cacheKey)
        return reports[period.cacheKey]
    }

    func apps() async throws -> [String: AppStoreApp] { knownApps }

    func requestCount(for period: SalesPeriod) -> Int {
        requested.filter { $0 == period.cacheKey }.count
    }
}

@Suite("Apple installs service")
struct AppleInstallsServiceTests {
    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private static func report(units: Int, title: String = "Бюро Знахідок", identifier: String = "6789246448") -> SalesReport {
        try! SalesReport(tsv: """
        SKU\tTitle\tProduct Type Identifier\tUnits\tApple Identifier
        finder\t\(title)\t1T\t\(units)\t\(identifier)
        """)
    }

    /// A store per test, in a temporary directory — the real one lives in
    /// Application Support and must not be touched by a test run.
    private static func store() -> InstallHistoryStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app-meter-tests-\(UUID().uuidString).json")
        return InstallHistoryStore(url: url)
    }

    private static let secondOfJanuary = date("2026-01-02T12:00:00Z")

    /// The plan on 2 January is three yearly reports and two daily ones, so a
    /// small fixture covers a whole lifetime.
    @Test func sumsTheWholePlanIntoALifetimeTotal() async throws {
        let source = StubSource([
            .yearly(2024): Self.report(units: 100),
            .yearly(2025): Self.report(units: 40),
            .daily(year: 2026, month: 1, day: 1): Self.report(units: 3),
            .daily(year: 2026, month: 1, day: 2): Self.report(units: 2),
        ])

        let figures = try await AppleInstallsService(client: source, history: Self.store())
            .figures(now: Self.secondOfJanuary)

        #expect(figures.count == 1)
        #expect(figures[0].lifetime == 145)
        #expect(figures[0].name == "Бюро Знахідок")
        #expect(figures[0].store == .appStore)
    }

    /// "Today" is the newest daily report that had anything in it, not the
    /// calendar day — Apple publishes a day behind.
    @Test func todayIsTheNewestDayWithFigures() async throws {
        let source = StubSource([
            .daily(year: 2026, month: 1, day: 1): Self.report(units: 7),
            // 2 January has no report yet, the usual state of affairs
        ])

        let figures = try await AppleInstallsService(client: source, history: Self.store())
            .figures(now: Self.secondOfJanuary)

        #expect(figures[0].today == 7)
        #expect(figures[0].asOf == Self.date("2026-01-01T00:00:00Z"))
    }

    /// The point of the cache: a closed period is fetched once ever, however
    /// many refreshes follow.
    @Test func closedPeriodsAreFetchedOnce() async throws {
        let source = StubSource([.yearly(2025): Self.report(units: 40)])
        let history = Self.store()
        let service = AppleInstallsService(client: source, history: history)

        _ = try await service.figures(now: Self.secondOfJanuary)
        _ = try await service.figures(now: Self.secondOfJanuary)

        #expect(await source.requestCount(for: .yearly(2025)) == 1)
    }

    /// And the other half of it: today's report is still being written, so it
    /// must be re-read every time rather than remembered.
    @Test func theOpenDayIsFetchedEveryTime() async throws {
        let today = SalesPeriod.daily(year: 2026, month: 1, day: 2)
        let source = StubSource([today: Self.report(units: 2)])
        let service = AppleInstallsService(client: source, history: Self.store())

        _ = try await service.figures(now: Self.secondOfJanuary)
        _ = try await service.figures(now: Self.secondOfJanuary)

        #expect(await source.requestCount(for: today) == 2)
    }

    /// A partial day must never be summed twice, or the total climbs by the
    /// day's figures on every refresh.
    @Test func repeatedRefreshesDoNotInflateTheTotal() async throws {
        let source = StubSource([
            .yearly(2025): Self.report(units: 40),
            .daily(year: 2026, month: 1, day: 2): Self.report(units: 2),
        ])
        let service = AppleInstallsService(client: source, history: Self.store())

        let first = try await service.figures(now: Self.secondOfJanuary)
        let second = try await service.figures(now: Self.secondOfJanuary)

        #expect(first[0].lifetime == 42)
        #expect(second[0].lifetime == 42)
    }

    private static let thirdOfFebruary = date("2026-02-03T12:00:00Z")

    /// The month Apple has not summarised yet. It happens every first of the
    /// month: the day the monthly report becomes the plan's way of covering
    /// January is the day before Apple publishes it. Falling back to the days
    /// of that month is what keeps the lifetime total from collapsing.
    @Test func aMonthWithNoReportYetIsCoveredByItsDays() async throws {
        let source = StubSource([
            // No .monthly(2026, 1) — Apple answers 404 for it on 3 February.
            .daily(year: 2026, month: 1, day: 15): Self.report(units: 12),
            .daily(year: 2026, month: 2, day: 2): Self.report(units: 5),
        ])

        let figures = try await AppleInstallsService(client: source, history: Self.store())
            .figures(now: Self.thirdOfFebruary)

        #expect(figures.count == 1)
        #expect(figures[0].lifetime == 17)
        // And the newest day is still February's, not the January day fetched
        // after it.
        #expect(figures[0].today == 5)
        #expect(figures[0].asOf == Self.date("2026-02-02T00:00:00Z"))
    }

    /// "Apple has no report for this period" and "this period had nothing in
    /// it" arrive as the same 404. Remembering the first as zero is what froze
    /// a whole month's figures at nothing.
    @Test func aPeriodWithNoReportIsNotRememberedAsZero() async throws {
        let source = StubSource([.daily(year: 2026, month: 1, day: 15): Self.report(units: 12)])
        let history = Self.store()
        let service = AppleInstallsService(client: source, history: history)

        _ = try await service.figures(now: Self.thirdOfFebruary)
        _ = try await service.figures(now: Self.thirdOfFebruary)

        #expect(await source.requestCount(for: .monthly(year: 2026, month: 1)) == 2)
        // The days it fell back to are real answers, so those are cached.
        #expect(await source.requestCount(for: .daily(year: 2026, month: 1, day: 15)) == 1)
    }

    @Test func reportsNothingWhenNoPeriodHasFigures() async throws {
        let figures = try await AppleInstallsService(client: StubSource([:]), history: Self.store())
            .figures(now: Self.secondOfJanuary)
        #expect(figures.isEmpty)
    }

    @Test func keepsEveryAppApart() async throws {
        let source = StubSource([
            .yearly(2025): try! SalesReport(tsv: """
            SKU\tTitle\tProduct Type Identifier\tUnits\tApple Identifier
            one\tFirst App\t1T\t10\t111
            two\tSecond App\t1T\t25\t222
            """),
        ])

        let figures = try await AppleInstallsService(client: source, history: Self.store())
            .figures(now: Self.secondOfJanuary)

        #expect(figures.map(\.id) == ["111", "222"])
        #expect(figures.map(\.lifetime) == [10, 25])
        #expect(figures.map(\.name) == ["First App", "Second App"])
    }

    /// The bundle id is the only key the Play side can be matched on, so it
    /// replaces the Apple identifier wherever it is known.
    @Test func figuresAreKeyedByBundleIdWhenItIsKnown() async throws {
        let source = StubSource(
            [.yearly(2025): Self.report(units: 40)],
            apps: ["6789246448": AppStoreApp(bundleID: "com.biuroznakhidok.app", name: "Бюро Знахідок")]
        )

        let figures = try await AppleInstallsService(client: source, history: Self.store())
            .figures(now: Self.secondOfJanuary)

        #expect(figures[0].id == "com.biuroznakhidok.app")
        #expect(figures[0].name == "Бюро Знахідок")
    }

    /// A key that cannot list an app must not make that app's installs vanish.
    @Test func figuresSurviveAnAppTheKeyCannotList() async throws {
        let source = StubSource([.yearly(2025): Self.report(units: 40)], apps: [:])

        let figures = try await AppleInstallsService(client: source, history: Self.store())
            .figures(now: Self.secondOfJanuary)

        #expect(figures[0].id == "6789246448")
        #expect(figures[0].name == "Бюро Знахідок")
        #expect(figures[0].lifetime == 40)
    }

    /// An app re-created under a new Apple identifier keeps its bundle id, so
    /// both identifiers turn up in the history and must not become two rows —
    /// one of which would then quietly overwrite the other.
    @Test func twoIdentifiersSharingABundleIdBecomeOneApp() async throws {
        let source = StubSource(
            [.yearly(2025): try! SalesReport(tsv: """
            SKU\tTitle\tProduct Type Identifier\tUnits\tApple Identifier
            old\tFinder\t1T\t30\t111
            new\tFinder\t1T\t12\t222
            """)],
            apps: [
                "111": AppStoreApp(bundleID: "com.example.finder", name: "Finder"),
                "222": AppStoreApp(bundleID: "com.example.finder", name: "Finder"),
            ]
        )

        let figures = try await AppleInstallsService(client: source, history: Self.store())
            .figures(now: Self.secondOfJanuary)

        #expect(figures.count == 1)
        #expect(figures[0].id == "com.example.finder")
        #expect(figures[0].lifetime == 42)
    }
}
