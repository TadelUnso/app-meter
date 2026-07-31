import Foundation

/// Turns the Play reporting bucket into panel figures.
///
/// Far simpler than the Apple side, because Google does the accounting: the
/// monthly overview carries a cumulative column, so the lifetime total is the
/// last row of the newest month that has one. No history cache is needed.
public struct PlayInstallsService: Sendable {
    private let client: GooglePlayClient

    public init(client: GooglePlayClient) {
        self.client = client
    }

    public func figures(now: Date = Date()) async throws -> [AppFigures] {
        let token = try await client.accessToken()
        let packages = try await client.packageNames()

        var figures: [AppFigures] = []

        for package in packages {
            // The current month first; on the first days of a month, before its
            // file exists, the previous month is the newest there is.
            guard let latest = try await latestReport(for: package, now: now, token: token)?.latest else {
                continue
            }

            figures.append(AppFigures(
                id: package,
                // The bucket only knows package names. The display name is the
                // panel's to improve later; the package is at least stable.
                name: package,
                store: .googlePlay,
                lifetime: latest.totalUserInstalls,
                today: latest.dailyUserInstalls,
                asOf: latest.date
            ))
        }

        return figures
    }

    private func latestReport(for package: String, now: Date, token: String) async throws -> PlayInstallsReport? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Two months is as stale as a live account's newest file can be: the
        // current month's file appears a few days in, and the previous month's
        // always exists once the account has any history at all.
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month], from: day)
            guard let year = parts.year, let month = parts.month else { continue }

            if let report = try await client.installsReport(package: package, year: year, month: month, token: token),
               report.latest != nil {
                return report
            }
        }

        return nil
    }
}
