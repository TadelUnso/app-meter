import Foundation

/// Where a package's monthly reports come from. The one implementation that
/// matters is `GooglePlayClient`; the protocol exists so the summing below can
/// be tested without a bucket.
public protocol PlayReportSource: Sendable {
    func accessToken() async throws -> String
    func overviewMonths() async throws -> [String: [YearMonth]]
    func installsReport(package: String, year: Int, month: Int, token: String?) async throws -> PlayInstallsReport?
}

extension GooglePlayClient: PlayReportSource {}

/// Turns the Play reporting bucket into panel figures.
///
/// The lifetime total is summed from every monthly overview the bucket holds.
/// Google used to do this accounting itself in a `Total User Installs` column,
/// but that column has read zero in every row since the file changed shape at
/// the end of July 2026, so the sum is ours to do.
///
/// Uncached, unlike the Apple side: the months come from one bucket listing, so
/// there is no guessing and no 404s, and a monthly file is two kilobytes. An
/// app published for three years costs thirty-six small reads an hour.
public struct PlayInstallsService: Sendable {
    private let client: any PlayReportSource

    public init(client: any PlayReportSource) {
        self.client = client
    }

    public func figures() async throws -> [AppFigures] {
        let token = try await client.accessToken()
        let months = try await client.overviewMonths()

        var figures: [AppFigures] = []

        for package in months.keys.sorted() {
            var lifetime = 0
            var latest: PlayInstallsReport.Day?

            for month in months[package] ?? [] {
                guard let report = try await client.installsReport(
                    package: package, year: month.year, month: month.month, token: token
                ) else { continue }

                lifetime += report.userInstalls

                // The newest day across every file, not the newest file's last
                // day: Play backfills, so a month can gain rows after the next
                // month's file already exists.
                if let day = report.latest, day.date > (latest?.date ?? .distantPast) {
                    latest = day
                }
            }

            guard let latest else { continue }

            figures.append(AppFigures(
                id: package,
                // The bucket only knows package names. The display name is the
                // panel's to improve later; the package is at least stable.
                name: package,
                store: .googlePlay,
                lifetime: lifetime,
                today: latest.dailyUserInstalls,
                asOf: latest.date
            ))
        }

        return figures
    }
}
