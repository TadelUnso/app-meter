import Foundation
import Testing
@testable import AppMeterCore

@Suite("Play object names")
struct GooglePlayClientTests {
    @Test func readsThePackageOutOfAReportName() {
        #expect(GooglePlayClient.packageName(
            fromObjectName: "stats/installs/installs_com.tadelunso.finder_202607_overview.csv"
        ) == "com.tadelunso.finder")
    }

    /// Package names may contain underscores; the fixed-width date segment is
    /// what keeps them from being mistaken for the date.
    @Test func survivesUnderscoresInThePackage() {
        #expect(GooglePlayClient.packageName(
            fromObjectName: "stats/installs/installs_com.my_company.app_202607_overview.csv"
        ) == "com.my_company.app")
    }

    /// The prefix listing also matches the per-country and per-device variants;
    /// only the plain overview is wanted.
    @Test func ignoresTheOtherReportVariants() {
        #expect(GooglePlayClient.packageName(
            fromObjectName: "stats/installs/installs_com.example_202607_country.csv"
        ) == nil)
        #expect(GooglePlayClient.packageName(fromObjectName: "stats/installs/") == nil)
    }
}
