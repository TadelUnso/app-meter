import Foundation
import Testing
@testable import AppMeterCore

@Suite("Google Analytics install supplement")
struct GoogleAnalyticsInstallsServiceTests {
    actor Source: GoogleAnalyticsFirstOpenSource {
        let rows: [GoogleAnalyticsFirstOpen]
        private(set) var requests: [(Date, Date)] = []

        init(rows: [GoogleAnalyticsFirstOpen]) { self.rows = rows }

        func firstOpens(from start: Date, through end: Date) -> [GoogleAnalyticsFirstOpen] {
            requests.append((start, end))
            return rows
        }
    }

    @Test func addsOnlyTheUnconfirmedTail() async throws {
        let source = Source(rows: [
            .init(date: Self.day("2026-07-25"), count: 1),
            .init(date: Self.day("2026-07-24"), count: 2),
        ])
        let play = AppFigures(
            id: "com.example.app",
            name: "com.example.app",
            store: .googlePlay,
            lifetime: 9,
            today: 0,
            asOf: Self.day("2026-07-23")
        )

        let result = try await GoogleAnalyticsInstallsService(client: source)
            .supplement(play, now: Self.day("2026-07-26"))

        #expect(result.lifetime == 12)
        #expect(result.today == 0)
        #expect(result.asOf == Self.day("2026-07-26"))
        let requests = await source.requests
        #expect(requests.count == 1)
        #expect(requests.first?.0 == Self.day("2026-07-24"))
        #expect(requests.first?.1 == Self.day("2026-07-26"))
    }

    @Test func anEmptyAnalyticsAnswerStillAdvancesFreshness() async throws {
        let source = Source(rows: [])
        let play = AppFigures(
            id: "com.example.app",
            name: "com.example.app",
            store: .googlePlay,
            lifetime: 9,
            today: 0,
            asOf: Self.day("2026-07-23")
        )

        let result = try await GoogleAnalyticsInstallsService(client: source)
            .supplement(play, now: Self.day("2026-07-26"))
        #expect(result.lifetime == play.lifetime)
        #expect(result.today == 0)
        #expect(result.asOf == Self.day("2026-07-26"))
    }

    @Test func doesNotQueryWithoutAConfirmedPlayDay() async throws {
        let source = Source(rows: [.init(date: Self.day("2026-07-24"), count: 2)])
        let play = AppFigures(
            id: "com.example.app",
            name: "com.example.app",
            store: .googlePlay,
            lifetime: 9,
            today: 0,
            asOf: nil
        )

        let result = try await GoogleAnalyticsInstallsService(client: source).supplement(play)
        #expect(result == play)
        #expect(await source.requests.isEmpty)
    }

    private static func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }
}
