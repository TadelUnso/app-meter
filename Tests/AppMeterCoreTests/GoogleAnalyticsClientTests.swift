import Foundation
import Testing
@testable import AppMeterCore

@Suite("Google Analytics Data API")
struct GoogleAnalyticsClientTests {
    @Test func reportRequestsOnlyFirstOpensForOneAndroidStream() throws {
        let body = GoogleAnalyticsClient.reportBody(
            from: Self.day("2026-08-01"),
            through: Self.day("2026-08-03"),
            streamID: "9876543210"
        )
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\"startDate\":\"2026-08-01\""))
        #expect(text.contains("\"endDate\":\"2026-08-03\""))
        #expect(text.contains("\"fieldName\":\"eventName\""))
        #expect(text.contains("\"value\":\"first_open\""))
        #expect(text.contains("\"fieldName\":\"platform\""))
        #expect(text.contains("\"value\":\"Android\""))
        #expect(text.contains("\"fieldName\":\"streamId\""))
        #expect(text.contains("\"value\":\"9876543210\""))
    }

    @Test func parsesDatedCounts() throws {
        let data = Data(#"{"rows":[{"dimensionValues":[{"value":"20260801"}],"metricValues":[{"value":"2"}]},{"dimensionValues":[{"value":"20260802"}],"metricValues":[{"value":"1"}]}]}"#.utf8)
        let rows = try GoogleAnalyticsClient.firstOpens(from: data)

        #expect(rows == [
            GoogleAnalyticsFirstOpen(date: Self.day("2026-08-01"), count: 2),
            GoogleAnalyticsFirstOpen(date: Self.day("2026-08-02"), count: 1),
        ])
    }

    @Test func acceptsAReportWithNoRows() throws {
        #expect(try GoogleAnalyticsClient.firstOpens(from: Data("{}".utf8)) == [])
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
