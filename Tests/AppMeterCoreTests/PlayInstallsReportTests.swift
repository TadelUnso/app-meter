import Foundation
import Testing
@testable import AppMeterCore

@Suite("Play installs report")
struct PlayInstallsReportTests {
    /// Column set and quoting follow a real installs overview file as Play
    /// wrote it before the July 2026 change.
    private static let csv = """
    "Date","Package Name","Daily Device Installs","Daily Device Uninstalls","Daily Device Upgrades","Total User Installs","Daily User Installs","Daily User Uninstalls","Active Device Installs"
    2026-07-26,com.tadelunso.finder,4,1,0,120,3,1,98
    2026-07-27,com.tadelunso.finder,6,0,2,126,6,0,104
    2026-07-28,com.tadelunso.finder,2,1,1,128,2,1,105
    """

    private static func utf16(_ text: String, littleEndian: Bool = true) -> Data {
        var data = Data(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
        data.append(text.data(using: littleEndian ? .utf16LittleEndian : .utf16BigEndian)!)
        return data
    }

    @Test func readsAUTF16FileWithABOM() throws {
        let report = try PlayInstallsReport(csv: Self.utf16(Self.csv))
        #expect(report.days.count == 3)
        #expect(report.days.first?.packageName == "com.tadelunso.finder")
    }

    @Test func readsBigEndianToo() throws {
        let report = try PlayInstallsReport(csv: Self.utf16(Self.csv, littleEndian: false))
        #expect(report.days.count == 3)
    }

    /// The month's own figure is the sum of its days. Google's cumulative
    /// column reads zero in every row now, so nothing may be taken from it.
    @Test func theMonthsInstallsAreTheSumOfItsDays() throws {
        let report = try PlayInstallsReport(csv: Self.utf16(Self.csv))
        #expect(report.userInstalls == 11)
    }

    @Test func theLatestDayIsTheNewestRow() throws {
        let latest = try #require(try PlayInstallsReport(csv: Self.utf16(Self.csv)).latest)
        #expect(latest.dailyUserInstalls == 2)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.dateComponents([.year, .month, .day], from: latest.date).day == 28)
    }

    /// A comma inside a quoted field must not become a column break.
    @Test func quotedFieldsMayContainCommas() throws {
        let csv = """
        "Date","Package Name","Total User Installs","Daily User Installs"
        2026-07-28,"com.example.app, ltd",128,2
        """
        let report = try PlayInstallsReport(text: csv)
        #expect(report.latest?.packageName == "com.example.app, ltd")
        #expect(report.latest?.dailyUserInstalls == 2)
    }

    /// The shape Play switched to at the end of July 2026: no quoting, the
    /// package column renamed, three columns appended, and the cumulative
    /// column left at zero.
    @Test func readsTheShapePlaySwitchedTo() throws {
        let csv = """
        Date,Package name,Daily Device Installs,Daily Device Uninstalls,Daily Device Upgrades,Total User Installs,Daily User Installs,Daily User Uninstalls,Active Device Installs,Install events,Update events,Uninstall events
        2026-07-08,com.biuroznakhidok.app,0,0,0,0,0,0,0,0,1,0
        2026-07-09,com.biuroznakhidok.app,10,0,0,0,9,0,8,10,0,0
        """
        let report = try PlayInstallsReport(text: csv)
        #expect(report.days.count == 2)
        #expect(report.userInstalls == 9)
        #expect(report.latest?.packageName == nil)
    }

    @Test func complainsAboutAFileThatIsNotAnInstallsReport() {
        let csv = "\"Date\",\"Package Name\",\"Crashes\"\n2026-07-28,com.example,3"
        #expect(throws: PlayInstallsReport.Failure.self) { try PlayInstallsReport(text: csv) }
    }

    @Test func complainsAboutBytesThatAreNotText() {
        // Lone high surrogates: not valid UTF-8, and no BOM to claim otherwise.
        let data = Data([0xED, 0xA0, 0x80, 0xED, 0xA0, 0x80])
        #expect(throws: PlayInstallsReport.Failure.unreadableEncoding) { try PlayInstallsReport(csv: data) }
    }

    /// A month with no data yet is a header and nothing else.
    @Test func acceptsAFileWithNoDays() throws {
        let header = String(Self.csv.split(whereSeparator: \.isNewline).first!)
        let report = try PlayInstallsReport(text: header)
        #expect(report.days.isEmpty)
        #expect(report.latest == nil)
        #expect(report.userInstalls == 0)
    }
}
