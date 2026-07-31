import Foundation

public enum GooglePlayError: LocalizedError {
    case tokenExchangeFailed(String)
    case unauthorized
    case http(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case let .tokenExchangeFailed(detail):
            "Google would not issue an access token: \(detail)"
        case .unauthorized:
            "Google Cloud Storage rejected the service account. Check that it was invited in Play Console with the download-reports permission."
        case let .http(status, body):
            "Google Cloud Storage answered \(status): \(body)"
        }
    }
}

/// Reads install reports out of the Play Console reporting bucket.
///
/// Play exports one CSV per app per month, named
/// `stats/installs/installs_<package>_<yyyyMM>_overview.csv`. The names are
/// predictable, so there is no need to list the bucket for the current month —
/// but discovering which apps exist at all does take one listing.
public struct GooglePlayClient: Sendable {
    private let account: GoogleServiceAccount
    private let privateKeyPEM: String
    private let bucket: String
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(
        account: GoogleServiceAccount,
        privateKeyPEM: String,
        bucket: String,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.account = account
        self.privateKeyPEM = privateKeyPEM
        self.bucket = bucket
        self.session = session
        self.now = now
    }

    // MARK: Access token

    /// Trades the signed assertion for a bearer token.
    ///
    /// Minted fresh per refresh rather than cached: a refresh is at most hourly
    /// and the exchange is one request, so caching would save nothing and add
    /// an expiry to get wrong.
    func accessToken() async throws -> String {
        let assertion = try GoogleServiceAccountToken.make(
            clientEmail: account.clientEmail,
            privateKeyPEM: privateKeyPEM,
            now: now()
        )

        var request = URLRequest(url: URL(string: GoogleServiceAccountToken.audience)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(assertion)".utf8
        )

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GooglePlayError.tokenExchangeFailed(
                String(data: data.prefix(300), encoding: .utf8) ?? "unreadable"
            )
        }

        struct TokenResponse: Decodable { let access_token: String }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw GooglePlayError.tokenExchangeFailed("the token response had no access_token")
        }
        return token.access_token
    }

    // MARK: Bucket reads

    /// The packages that have ever had an installs report: one listing of the
    /// installs prefix, reduced to the package names in the filenames.
    public func packageNames() async throws -> [String] {
        var components = URLComponents(string: "https://storage.googleapis.com/storage/v1/b/\(bucket)/o")!
        components.queryItems = [
            URLQueryItem(name: "prefix", value: "stats/installs/installs_"),
            URLQueryItem(name: "fields", value: "items(name),nextPageToken"),
        ]

        struct Listing: Decodable {
            struct Item: Decodable { let name: String }
            let items: [Item]?
            let nextPageToken: String?
        }

        var names: Set<String> = []
        var pageToken: String?
        let token = try await accessToken()

        repeat {
            var pageComponents = components
            if let pageToken {
                pageComponents.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let data = try await get(pageComponents.url!, token: token)
            let listing = try JSONDecoder().decode(Listing.self, from: data)

            for item in listing.items ?? [] {
                if let package = Self.packageName(fromObjectName: item.name) {
                    names.insert(package)
                }
            }
            pageToken = listing.nextPageToken
        } while pageToken != nil

        return names.sorted()
    }

    /// One month's overview for one package, nil when that month has no file
    /// yet — January's report does not exist on the first of January.
    ///
    /// Pass a `token` when making several reads in a row; without one the call
    /// performs its own exchange.
    public func installsReport(package: String, year: Int, month: Int, token: String? = nil) async throws -> PlayInstallsReport? {
        let object = "stats/installs/installs_\(package)_\(String(format: "%04d%02d", year, month))_overview.csv"
        let escaped = object.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? object
        let url = URL(string: "https://storage.googleapis.com/storage/v1/b/\(bucket)/o/\(escaped)?alt=media")!

        let bearer: String
        if let token {
            bearer = token
        } else {
            bearer = try await accessToken()
        }

        do {
            return try PlayInstallsReport(csv: try await get(url, token: bearer))
        } catch GooglePlayError.http(status: 404, body: _) {
            return nil
        }
    }

    /// `installs_<package>_<yyyyMM>_overview.csv` → the package. Underscores
    /// in the package name cannot confuse this: the tail two segments are
    /// fixed, and everything between the first segment and them is the name.
    static func packageName(fromObjectName name: String) -> String? {
        guard let filename = name.split(separator: "/").last,
              filename.hasSuffix("_overview.csv"),
              filename.hasPrefix("installs_")
        else { return nil }

        let trimmed = filename.dropFirst("installs_".count).dropLast("_overview.csv".count)
        // What remains is <package>_<yyyyMM>; the date segment is fixed-width.
        guard let separator = trimmed.lastIndex(of: "_"),
              trimmed[trimmed.index(after: separator)...].count == 6
        else { return nil }

        return String(trimmed[..<separator])
    }

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GooglePlayError.http(status: 0, body: "no response")
        }

        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            NSLog("[sales] google %d body: %@", http.statusCode,
                  String(data: data.prefix(400), encoding: .utf8) ?? "unreadable")
            throw GooglePlayError.unauthorized
        default:
            throw GooglePlayError.http(
                status: http.statusCode,
                body: String(data: data.prefix(300), encoding: .utf8) ?? "unreadable"
            )
        }
    }
}
