import Foundation
import Testing
@testable import AppMeterCore

@Suite("Google Analytics Data API")
struct GoogleAnalyticsClientTests {
    @Test func reportRequestsOnlyFirstOpensForOneAndroidStream() throws {
        let body = GoogleAnalyticsClient.reportBody(
            from: Self.day("2026-08-01"),
            streamID: "9876543210"
        )
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\"startDate\":\"2026-08-01\""))
        // Not a computed date: only the property knows when its own day ends,
        // and a date worked out here in UTC can cut its current day short.
        #expect(text.contains("\"endDate\":\"today\""))
        #expect(text.contains("\"fieldName\":\"eventName\""))
        #expect(text.contains("\"value\":\"first_open\""))
        #expect(text.contains("\"fieldName\":\"platform\""))
        #expect(text.contains("\"value\":\"Android\""))
        #expect(text.contains("\"fieldName\":\"streamId\""))
        #expect(text.contains("\"value\":\"9876543210\""))
    }

    @Test func parsesDatedCounts() throws {
        let data = Data(#"{"rows":[{"dimensionValues":[{"value":"20260801"}],"metricValues":[{"value":"2"}]},{"dimensionValues":[{"value":"20260802"}],"metricValues":[{"value":"1"}]}],"metadata":{"timeZone":"Etc/GMT-3"}}"#.utf8)
        let report = try GoogleAnalyticsClient.firstOpens(from: data)

        #expect(report.days == [
            GoogleAnalyticsFirstOpen(date: Self.day("2026-08-01"), count: 2),
            GoogleAnalyticsFirstOpen(date: Self.day("2026-08-02"), count: 1),
        ])
        #expect(report.timeZone == TimeZone(identifier: "Etc/GMT-3"))
    }

    /// The row dates stay UTC-anchored labels whatever the property's zone is —
    /// that is the one calendar the whole panel dates figures in. The zone is
    /// carried separately, for deciding which of those labels is today.
    @Test func rowDatesAreLabelsNotPropertyLocalInstants() throws {
        let data = Data(#"{"rows":[{"dimensionValues":[{"value":"20260801"}],"metricValues":[{"value":"2"}]}],"metadata":{"timeZone":"America/Los_Angeles"}}"#.utf8)
        let report = try GoogleAnalyticsClient.firstOpens(from: data)

        #expect(report.days.first?.date == Self.day("2026-08-01"))
        #expect(report.timeZone == TimeZone(identifier: "America/Los_Angeles"))
    }

    /// A response without metadata is not worth losing the counts over; UTC is
    /// the same assumption the panel makes everywhere else.
    @Test func fallsBackToUTCWhenThePropertyZoneIsAbsent() throws {
        let data = Data(#"{"rows":[{"dimensionValues":[{"value":"20260801"}],"metricValues":[{"value":"2"}]}]}"#.utf8)
        let report = try GoogleAnalyticsClient.firstOpens(from: data)

        #expect(report.timeZone == TimeZone(identifier: "UTC"))
        #expect(report.days.count == 1)
    }

    @Test func acceptsAReportWithNoRows() throws {
        #expect(try GoogleAnalyticsClient.firstOpens(from: Data("{}".utf8)).days == [])
    }

    @Test func rejectsMalformedRows() {
        let data = Data(#"{"rows":[{"dimensionValues":[{"value":"not-a-day"}],"metricValues":[{"value":"2"}]}]}"#.utf8)
        #expect(throws: GoogleAnalyticsError.self) {
            try GoogleAnalyticsClient.firstOpens(from: data)
        }
    }

    private static func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }
}
