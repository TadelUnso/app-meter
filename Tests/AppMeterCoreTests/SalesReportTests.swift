import Foundation
import Testing
@testable import AppMeterCore

@Suite("Sales report")
struct SalesReportTests {
    /// Column order and the trailing blank line follow a real SALES / SUMMARY
    /// file; the columns App Meter does not read are trimmed away, which is
    /// itself the case `columnsAreFoundByName` covers.
    private static let tsv = """
    Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\tUnits\tBegin Date\tApple Identifier
    APPLE\tUS\tfinder-app\tTadel Unso\tБюро Знахідок\t1.2\t1T\t12\t07/30/2026\t6478441234
    APPLE\tUS\tfinder-app\tTadel Unso\tБюро Знахідок\t1.2\t1\t3\t07/30/2026\t6478441234
    APPLE\tUS\tfinder-app\tTadel Unso\tБюро Знахідок\t1.2\t7T\t40\t07/30/2026\t6478441234
    APPLE\tUS\tfinder-app\tTadel Unso\tБюро Знахідок\t1.2\t3T\t5\t07/30/2026\t6478441234
    APPLE\tUS\tother-app\tTadel Unso\tSecond App\t2.0\t1T\t7\t07/30/2026\t6478449999

    """

    @Test func readsEveryRow() throws {
        let report = try SalesReport(tsv: Self.tsv)
        #expect(report.rows.count == 5)
        #expect(report.rows.first?.sku == "finder-app")
        #expect(report.rows.first?.units == 12)
        #expect(report.rows.first?.appleIdentifier == "6478441234")
    }

    /// Apple appends columns over time, so position cannot be trusted — here
    /// Apple Identifier sits last rather than in its historical place.
    @Test func columnsAreFoundByName() throws {
        let report = try SalesReport(tsv: Self.tsv)
        #expect(report.rows.allSatisfy { $0.appleIdentifier.hasPrefix("6478") })
    }

    @Test func sumsFirstDownloadsAndIgnoresUpdatesAndRedownloads() throws {
        let downloads = try SalesReport(tsv: Self.tsv).firstDownloads()

        // 12 universal + 3 iPhone; the 40 updates and 5 redownloads stay out.
        #expect(downloads["6478441234"]?.units == 15)
        #expect(downloads["6478441234"]?.title == "Бюро Знахідок")
        #expect(downloads["6478449999"]?.units == 7)
        #expect(downloads.count == 2)
    }

    /// A type App Meter has not seen must not be folded into the total on a
    /// guess — a wrong install count is worse than a missing one.
    @Test func ignoresAnUnknownProductType() throws {
        let tsv = Self.tsv.replacingOccurrences(of: "\t1T\t12\t", with: "\tZZ9\t12\t")
        let downloads = try SalesReport(tsv: tsv).firstDownloads()
        #expect(downloads["6478441234"]?.units == 3)
    }

    @Test func reportsEveryProductTypeForTheDump() throws {
        let totals = try SalesReport(tsv: Self.tsv).unitsByProductType()
        #expect(totals == ["1T": 19, "1": 3, "7T": 40, "3T": 5])
    }

    @Test func complainsAboutAFileThatIsNotASalesReport() {
        #expect(throws: SalesReport.Failure.self) {
            try SalesReport(tsv: "Date\tInstalls\n07/30/2026\t5\n")
        }
    }

    @Test func complainsAboutUnitsThatAreNotANumber() {
        let tsv = Self.tsv.replacingOccurrences(of: "\t1T\t12\t", with: "\t1T\ttwelve\t")
        #expect(throws: SalesReport.Failure.self) { try SalesReport(tsv: tsv) }
    }

    /// Apple serves an empty report — header only — for a day with no sales at
    /// all, and that is not an error.
    @Test func acceptsAReportWithNoRows() throws {
        let header = String(Self.tsv.split(whereSeparator: \.isNewline).first!)
        #expect(try SalesReport(tsv: header).rows.isEmpty)
        #expect(try SalesReport(tsv: header).firstDownloads().isEmpty)
    }
}
