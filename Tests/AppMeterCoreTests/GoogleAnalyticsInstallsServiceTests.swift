import Foundation
import Testing
@testable import AppMeterCore

@Suite("Google Analytics install supplement")
struct GoogleAnalyticsInstallsServiceTests {
    actor Source: GoogleAnalyticsFirstOpenSource {
        let rows: [GoogleAnalyticsFirstOpen]
        let zone: TimeZone
        private(set) var requests: [Date] = []

        init(rows: [GoogleAnalyticsFirstOpen], zone: TimeZone = TimeZone(identifier: "UTC")!) {
            self.rows = rows
            self.zone = zone
        }

        func firstOpens(since start: Date) -> GoogleAnalyticsFirstOpens {
            requests.append(start)
            return GoogleAnalyticsFirstOpens(days: rows, timeZone: zone)
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
        #expect(requests == [Self.day("2026-07-24")])
    }

    /// The property dates its rows by its own clock. A property three hours
    /// ahead of UTC has already begun a new day while UTC is still in the old
    /// one, and for those three hours the day's movement belongs to the row
    /// UTC has not reached yet.
    @Test func theDayIsThePropertysDayNotUTCs() async throws {
        let source = Source(
            rows: [
                .init(date: Self.day("2026-08-06"), count: 2),
                .init(date: Self.day("2026-08-07"), count: 5),
            ],
            zone: TimeZone(identifier: "Etc/GMT-3")!
        )
        let play = AppFigures(
            id: "com.example.app",
            name: "com.example.app",
            store: .googlePlay,
            lifetime: 9,
            today: 0,
            asOf: Self.day("2026-08-01")
        )

        // 22:00 UTC is already 01:00 the next day in the property's zone.
        let result = try await GoogleAnalyticsInstallsService(client: source)
            .supplement(play, now: Self.instant("2026-08-06 22:00"))

        #expect(result.today == 5)
        #expect(result.asOf == Self.day("2026-08-07"))
        #expect(result.lifetime == 16)
    }

    /// The same instant, read by a property behind UTC rather than ahead of it.
    @Test func aPropertyBehindUTCKeepsTheEarlierDay() async throws {
        let source = Source(
            rows: [
                .init(date: Self.day("2026-08-05"), count: 4),
                .init(date: Self.day("2026-08-06"), count: 7),
            ],
            zone: TimeZone(identifier: "America/Los_Angeles")!
        )
        let play = AppFigures(
            id: "com.example.app",
            name: "com.example.app",
            store: .googlePlay,
            lifetime: 0,
            today: 0,
            asOf: Self.day("2026-08-01")
        )

        // 03:00 UTC is still the previous evening in Los Angeles.
        let result = try await GoogleAnalyticsInstallsService(client: source)
            .supplement(play, now: Self.instant("2026-08-06 03:00"))

        #expect(result.today == 4)
        #expect(result.asOf == Self.day("2026-08-05"))
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

    private static func instant(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
}
