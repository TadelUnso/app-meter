import Foundation

public enum GoogleAnalyticsError: LocalizedError {
    case tokenExchangeFailed(String)
    case unauthorized
    case http(status: Int, body: String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case let .tokenExchangeFailed(detail):
            "Google would not issue an Analytics access token: \(detail)"
        case .unauthorized:
            "Google Analytics rejected the service account. Grant its email Viewer access to the GA4 property and enable the Google Analytics Data API."
        case let .http(status, body):
            "Google Analytics answered \(status): \(body)"
        case .malformedResponse:
            "Google Analytics returned a report App Meter could not read."
        }
    }
}

public struct GoogleAnalyticsFirstOpen: Equatable, Sendable {
    public let date: Date
    public let count: Int

    public init(date: Date, count: Int) {
        self.date = date
        self.count = count
    }
}

/// A report's rows together with the clock they were dated by.
///
/// The dates in `days` are UTC-anchored labels, like every other day the panel
/// handles. The zone is what GA4 used to decide which events fell on which of
/// those labels, and the caller needs it to work out which label is the current
/// day — a question UTC cannot answer for a property that is not on UTC.
public struct GoogleAnalyticsFirstOpens: Equatable, Sendable {
    public let days: [GoogleAnalyticsFirstOpen]
    public let timeZone: TimeZone

    public init(days: [GoogleAnalyticsFirstOpen], timeZone: TimeZone) {
        self.days = days
        self.timeZone = timeZone
    }
}

public protocol GoogleAnalyticsFirstOpenSource: Sendable {
    /// Everything from `start` up to and including the property's current day.
    /// There is no end parameter: the end is always "as recent as GA4 has", and
    /// only the property knows when its own day ends.
    func firstOpens(since start: Date) async throws -> GoogleAnalyticsFirstOpens
}

/// Reads Android `first_open` events from the GA4 Data API. Firebase logs the
/// event automatically on the first launch after an install or reinstall.
public struct GoogleAnalyticsClient: GoogleAnalyticsFirstOpenSource, Sendable {
    public static let scope = "https://www.googleapis.com/auth/analytics.readonly"

    private let account: GoogleServiceAccount
    private let privateKeyPEM: String
    private let propertyID: String
    private let streamID: String
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(
        account: GoogleServiceAccount,
        privateKeyPEM: String,
        propertyID: String,
        streamID: String,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.account = account
        self.privateKeyPEM = privateKeyPEM
        self.propertyID = propertyID
        self.streamID = streamID
        self.session = session
        self.now = now
    }

    public func firstOpens(since start: Date) async throws -> GoogleAnalyticsFirstOpens {
        let assertion = try GoogleServiceAccountToken.make(
            clientEmail: account.clientEmail,
            privateKeyPEM: privateKeyPEM,
            now: now(),
            scope: Self.scope
        )
        let token = try await accessToken(assertion: assertion)

        let url = URL(string: "https://analyticsdata.googleapis.com/v1beta/properties/\(propertyID):runReport")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.reportBody(from: start, streamID: streamID)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleAnalyticsError.http(status: 0, body: "no response")
        }
        switch http.statusCode {
        case 200:
            return try Self.firstOpens(from: data)
        case 401, 403:
            throw GoogleAnalyticsError.unauthorized
        default:
            throw GoogleAnalyticsError.http(
                status: http.statusCode,
                body: String(data: data.prefix(300), encoding: .utf8) ?? "unreadable"
            )
        }
    }

    private func accessToken(assertion: String) async throws -> String {
        var request = URLRequest(url: URL(string: GoogleServiceAccountToken.audience)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(assertion)".utf8
        )

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GoogleAnalyticsError.tokenExchangeFailed(
                String(data: data.prefix(300), encoding: .utf8) ?? "unreadable"
            )
        }

        struct TokenResponse: Decodable { let access_token: String }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw GoogleAnalyticsError.tokenExchangeFailed("the token response had no access_token")
        }
        return token.access_token
    }

    /// `startDate` is formatted in UTC because that is the calendar the date
    /// came from: it is Play's newest report day plus one, and Play's report
    /// days are parsed as UTC labels. `endDate` is GA4's own `today` keyword
    /// rather than a date worked out here — the property resolves it against
    /// its own clock, which is the only clock that knows when its day ends.
    static func reportBody(from start: Date, streamID: String) -> [String: Any] {
        [
            "dateRanges": [["startDate": requestDay.string(from: start), "endDate": "today"]],
            "dimensions": [["name": "date"]],
            "metrics": [["name": "eventCount"]],
            "dimensionFilter": [
                "andGroup": [
                    "expressions": [
                        ["filter": ["fieldName": "eventName", "stringFilter": ["matchType": "EXACT", "value": "first_open"]]],
                        ["filter": ["fieldName": "platform", "stringFilter": ["matchType": "EXACT", "value": "Android"]]],
                        ["filter": ["fieldName": "streamId", "stringFilter": ["matchType": "EXACT", "value": streamID]]],
                    ]
                ]
            ],
            "orderBys": [["dimension": ["dimensionName": "date"], "desc": false]],
        ]
    }

    static func firstOpens(from data: Data) throws -> GoogleAnalyticsFirstOpens {
        struct Response: Decodable {
            struct Value: Decodable { let value: String }
            struct Row: Decodable {
                let dimensionValues: [Value]
                let metricValues: [Value]
            }
            struct Metadata: Decodable { let timeZone: String? }
            let rows: [Row]?
            let metadata: Metadata?
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw GoogleAnalyticsError.malformedResponse
        }

        let days = try (response.rows ?? []).map { row in
            guard let dateText = row.dimensionValues.first?.value,
                  let date = responseDay.date(from: dateText),
                  let countText = row.metricValues.first?.value,
                  let count = Int(countText)
            else { throw GoogleAnalyticsError.malformedResponse }
            return GoogleAnalyticsFirstOpen(date: date, count: count)
        }

        // An unreadable or absent zone falls back to UTC rather than failing:
        // the counts are still right, and UTC is what the rest of the panel
        // assumes anyway. Only the "which row is today" question degrades.
        let zone = response.metadata?.timeZone.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(identifier: "UTC")!

        return GoogleAnalyticsFirstOpens(days: days, timeZone: zone)
    }

    private static let requestDay: DateFormatter = dayFormatter("yyyy-MM-dd")
    private static let responseDay: DateFormatter = dayFormatter("yyyyMMdd")

    private static func dayFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}
