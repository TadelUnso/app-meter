import Foundation
import Testing
@testable import AppMeterCore

@Suite("Play object names")
struct GooglePlayClientTests {
    @Test func readsThePackageAndMonthOutOfAReportName() {
        let file = GooglePlayClient.overviewFile(
            fromObjectName: "stats/installs/installs_com.tadelunso.finder_202607_overview.csv"
        )
        #expect(file?.package == "com.tadelunso.finder")
        #expect(file?.month == YearMonth(year: 2026, month: 7))
    }

    /// Package names may contain underscores; the fixed-width date segment is
    /// what keeps them from being mistaken for the date.
    @Test func survivesUnderscoresInThePackage() {
        #expect(GooglePlayClient.overviewFile(
            fromObjectName: "stats/installs/installs_com.my_company.app_202607_overview.csv"
        )?.package == "com.my_company.app")
    }

    /// The prefix listing also matches the per-country and per-device variants;
    /// only the plain overview is wanted.
    @Test func ignoresTheOtherReportVariants() {
        #expect(GooglePlayClient.overviewFile(
            fromObjectName: "stats/installs/installs_com.example_202607_country.csv"
        ) == nil)
        #expect(GooglePlayClient.overviewFile(fromObjectName: "stats/installs/") == nil)
    }

    /// Six digits that are not a month are not a date segment.
    @Test func rejectsAStampThatIsNotAMonth() {
        #expect(GooglePlayClient.overviewFile(
            fromObjectName: "stats/installs/installs_com.example_202613_overview.csv"
        ) == nil)
    }

    /// Chronological order, which is what summing a lifetime walks in.
    @Test func monthsSortByYearThenMonth() {
        let months = [
            YearMonth(year: 2026, month: 1),
            YearMonth(year: 2025, month: 12),
            YearMonth(year: 2026, month: 2),
        ].sorted()

        #expect(months == [
            YearMonth(year: 2025, month: 12),
            YearMonth(year: 2026, month: 1),
            YearMonth(year: 2026, month: 2),
        ])
    }
}
