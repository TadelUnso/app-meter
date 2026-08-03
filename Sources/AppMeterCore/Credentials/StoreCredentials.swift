import Foundation

/// Shape checks for the App Store Connect half of the credentials.
///
/// Pure string tests, deliberately no network: the point is to catch a pasted
/// wrong field — the key id in the issuer box, a whole download folder path in
/// place of a vendor number — before the first request, not to prove the
/// credentials work. Only the request itself can do that.
public enum AppStoreConnectCredentials {
    /// The issuer id is a UUID, printed under Users and Access → Integrations.
    public static func isValidIssuerID(_ value: String) -> Bool {
        UUID(uuidString: value.trimmed) != nil
    }

    /// Ten alphanumerics, and the same string that appears in the .p8 filename
    /// (`AuthKey_<keyID>.p8`).
    public static func isValidKeyID(_ value: String) -> Bool {
        let trimmed = value.trimmed
        return trimmed.count == 10 && trimmed.allSatisfy(\.isAlphanumericASCII)
    }

    /// Digits only. The length is not pinned: Apple has issued vendor numbers of
    /// more than one width, and a wrong guess here would lock out a valid account.
    public static func isValidVendorNumber(_ value: String) -> Bool {
        let trimmed = value.trimmed
        return !trimmed.isEmpty && trimmed.allSatisfy(\.isNumberASCII)
    }

    /// Accepts the .p8 as downloaded and hands back the trimmed PEM, or nil if
    /// the file is not a PKCS#8 private key at all.
    public static func privateKey(fromPEM text: String) -> String? {
        let trimmed = text.trimmed
        guard trimmed.contains("-----BEGIN PRIVATE KEY-----"),
              trimmed.contains("-----END PRIVATE KEY-----")
        else { return nil }
        return trimmed
    }
}

/// The fields App Meter needs out of a Google service account JSON.
///
/// Stored whole in the keychain; this is only the parse that tells the Settings
/// form whether the file it was handed is the right kind of file, and which
/// account it belongs to.
public struct GoogleServiceAccount: Equatable, Sendable {
    public let clientEmail: String
    public let projectID: String

    private struct Payload: Decodable {
        let type: String?
        let client_email: String?
        let private_key: String?
        let project_id: String?
    }

    /// Fails on anything that is not a service account key: a downloaded OAuth
    /// client, an API key, or a truncated file.
    public init?(json: String) {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.type == "service_account",
              let email = payload.client_email, !email.isEmpty,
              let key = payload.private_key, key.contains("-----BEGIN PRIVATE KEY-----")
        else { return nil }

        clientEmail = email
        projectID = payload.project_id ?? ""
    }
}

/// The Cloud Storage bucket Play Console exports reports to, copied from
/// Download reports → Copy Cloud Storage URI.
public enum GooglePlayCredentials {
    /// Takes whatever the console's copy button produced and returns the bucket
    /// alone.
    ///
    /// That button does not hand over a bare bucket: it copies the full prefix
    /// of the section it sits next to, `gs://pubsite_prod_…/stats/installs/`.
    /// The path is dropped rather than rejected — which report to read is App
    /// Meter's business, and making the user edit the string down by hand would
    /// be inviting a typo into the one field they could otherwise paste.
    public static func bucketName(from value: String) -> String? {
        var trimmed = value.trimmed
        if trimmed.hasPrefix("gs://") {
            trimmed = String(trimmed.dropFirst("gs://".count))
        }

        guard let bucket = trimmed.split(separator: "/").first.map(String.init),
              bucket.hasPrefix("pubsite_prod_")
        else { return nil }

        return bucket
    }
}

/// The non-secret identifiers for the optional GA4 first-open tail.
public enum GoogleAnalyticsCredentials {
    public static func isValidPropertyID(_ value: String) -> Bool {
        let trimmed = value.trimmed
        return !trimmed.isEmpty && trimmed.allSatisfy(\.isNumberASCII)
    }

    public static func isValidStreamID(_ value: String) -> Bool {
        isValidPropertyID(value)
    }

    public static func isValidPackageName(_ value: String) -> Bool {
        let parts = value.trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, first.isASCII, first.isLetter else { return false }
            return part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Character {
    var isAlphanumericASCII: Bool { isASCII && (isLetter || isNumber) }
    var isNumberASCII: Bool { isASCII && isNumber }
}
