import Foundation
import Testing
@testable import AppMeterCore

/// Answers with a fixed listing and a fixed report per package/month, so a
/// package's absence from `reports` reproduces the real client's 404 → nil.
private actor StubSource: PlayReportSource {
    private let months: [String: [YearMonth]]
    private let reports: [String: PlayInstallsReport]

    init(months: [String: [YearMonth]], reports: [String: PlayInstallsReport] = [:]) {
        self.months = months
        self.reports = reports
    }

    func accessToken() async throws -> String { "token" }

    func overviewMonths() async throws -> [String: [YearMonth]] { months }

    func installsReport(package: String, year: Int, month: Int, token: String?) async throws -> PlayInstallsReport? {
        reports["\(package)-\(year)-\(month)"]
    }
}

@Suite("Play installs service")
struct PlayInstallsServiceTests {
    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func date(_ ymd: String) -> Date { Self.dayFormat.date(from: ymd)! }

    /// Builds a report the way a real overview file reads, so the fixtures
    /// exercise the CSV parsing along with the summing.
    private static func report(_ days: [(String, Int)]) -> PlayInstallsReport {
        let header = "Date,Package Name,Daily User Installs"
        let rows = days.map { "\($0.0),com.example.app,\($0.1)" }
        return try! PlayInstallsReport(text: ([header] + rows).joined(separator: "\n"))
    }

    @Test func lifetimeIsTheSumOfEveryMonthNotJustTheNewest() async throws {
        let source = StubSource(
            months: ["com.example.app": [YearMonth(year: 2026, month: 6), YearMonth(year: 2026, month: 7)]],
            reports: [
                "com.example.app-2026-6": Self.report([("2026-06-01", 10), ("2026-06-02", 5)]),
                "com.example.app-2026-7": Self.report([("2026-07-01", 3)]),
            ]
        )

        let figures = try await PlayInstallsService(client: source).figures()

        #expect(figures.count == 1)
        #expect(figures[0].lifetime == 18)
    }

    /// Play backfills: June's file can gain a row dated after July's file
    /// already exists. "Today" has to be the newest day across every file, not
    /// the last row of whichever file is newest by name.
    @Test func todayIsTheNewestDayAcrossAllMonthsNotTheNewestFilesLastRow() async throws {
        let source = StubSource(
            months: ["com.example.app": [YearMonth(year: 2026, month: 6), YearMonth(year: 2026, month: 7)]],
            reports: [
                "com.example.app-2026-6": Self.report([("2026-06-01", 10), ("2026-07-15", 4)]),
                "com.example.app-2026-7": Self.report([("2026-07-01", 3), ("2026-07-10", 2)]),
            ]
        )

        let figures = try await PlayInstallsService(client: source).figures()

        #expect(figures[0].today == 4)
        #expect(figures[0].asOf == Self.date("2026-07-15"))
    }

    /// Every month 404s (the client's nil), which must not read as a real,
    /// empty app — it must not appear at all.
    @Test func aPackageWhoseEveryReportFailsToLoadIsLeftOutEntirely() async throws {
        let source = StubSource(
            months: ["com.example.app": [YearMonth(year: 2026, month: 6)]],
            reports: [:]
        )

        let figures = try await PlayInstallsService(client: source).figures()

        #expect(figures.isEmpty)
    }

    @Test func aPackageWithNoMonthsYieldsNoFigures() async throws {
        let source = StubSource(months: ["com.example.app": []])

        let figures = try await PlayInstallsService(client: source).figures()

        #expect(figures.isEmpty)
    }
}
