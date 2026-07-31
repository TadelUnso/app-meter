import Foundation

/// The four things a sales-report request needs. Assembled by the caller from
/// the defaults and the Keychain, so nothing here reads either.
public struct AppStoreConnectAccount: Equatable, Sendable {
    public let issuerID: String
    public let keyID: String
    public let vendorNumber: String
    public let privateKeyPEM: String

    public init(issuerID: String, keyID: String, vendorNumber: String, privateKeyPEM: String) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.vendorNumber = vendorNumber
        self.privateKeyPEM = privateKeyPEM
    }
}

public enum AppStoreConnectError: LocalizedError {
    case unauthorized
    case rateLimited
    case http(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "App Store Connect rejected the key. Check the issuer id, key id and .p8 in Settings."
        case .rateLimited:
            "App Store Connect is rate limiting the key. The next refresh will try again."
        case let .http(status, body):
            "App Store Connect answered \(status): \(body)"
        }
    }
}

/// Reads daily sales reports from App Store Connect.
///
/// One report is one day, and Apple has no endpoint for "the latest" — so the
/// caller asks for a specific day and gets nil when that day has no report,
/// which is both how a quiet day and a not-yet-published day look.
public struct AppStoreConnectClient: Sendable {
    private let account: AppStoreConnectAccount
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(
        account: AppStoreConnectAccount,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.account = account
        self.session = session
        self.now = now
    }

    public func report(for day: Date) async throws -> SalesReport? {
        let parts = SalesPeriods.calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { return nil }
        return try await report(for: .daily(year: year, month: month, day: dayOfMonth))
    }

    public func report(for period: SalesPeriod) async throws -> SalesReport? {
        var components = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/salesReports")!
        components.queryItems = [
            URLQueryItem(name: "filter[frequency]", value: period.frequency.rawValue),
            URLQueryItem(name: "filter[reportType]", value: "SALES"),
            URLQueryItem(name: "filter[reportSubType]", value: "SUMMARY"),
            URLQueryItem(name: "filter[vendorNumber]", value: account.vendorNumber),
            URLQueryItem(name: "filter[reportDate]", value: period.reportDate),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/a-gzip", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreConnectError.http(status: 0, body: "no response")
        }

        switch http.statusCode {
        case 200:
            return try SalesReport(tsv: try text(of: data))
        // Apple's answer for "that day has no report", whether because nothing
        // happened or because it is not published yet. Not an error.
        case 404:
            return nil
        case 401, 403:
            throw AppStoreConnectError.unauthorized
        case 429:
            throw AppStoreConnectError.rateLimited
        default:
            throw AppStoreConnectError.http(
                status: http.statusCode,
                body: String(data: data.prefix(500), encoding: .utf8) ?? "unreadable"
            )
        }
    }

    /// The most recent day that has a report, looking back from `from`.
    ///
    /// Apple publishes a day's report a day or so later, and a vendor with no
    /// activity gets no report at all — so the walk has to tolerate a run of
    /// empty days rather than concluding the credentials are wrong.
    public func latestReport(within days: Int = 5, from: Date? = nil) async throws -> (day: Date, report: SalesReport)? {
        let start = from ?? now()

        for offset in 0..<days {
            guard let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: -offset, to: start) else {
                continue
            }
            if let report = try await report(for: day) {
                return (day, report)
            }
        }

        return nil
    }

    private func token() throws -> String {
        try AppStoreConnectToken.make(
            issuerID: account.issuerID,
            keyID: account.keyID,
            privateKeyPEM: account.privateKeyPEM,
            now: now()
        )
    }

    /// Apple sends gzip, but has been known to send the report uncompressed
    /// when it is empty — so the magic decides, not the content type.
    private func text(of data: Data) throws -> String {
        let unpacked = data.starts(with: [0x1f, 0x8b]) ? try Gzip.inflate(data) : data
        guard let text = String(data: unpacked, encoding: .utf8) else {
            throw AppStoreConnectError.http(status: 200, body: "the report was not text")
        }
        return text
    }
}
