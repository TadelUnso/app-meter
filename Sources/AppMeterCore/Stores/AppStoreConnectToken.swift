import CryptoKit
import Foundation

/// Mints the bearer token the App Store Connect API expects: an ES256 JWT
/// signed with the `.p8` key.
///
/// Written out by hand rather than pulled from a JWT library — the whole of it
/// is three base64url segments and one P-256 signature, and CryptoKit already
/// ships with macOS. A dependency here would be more code to audit, not less.
public enum AppStoreConnectToken {
    public enum Failure: LocalizedError {
        case unreadableKey(String)

        public var errorDescription: String? {
            switch self {
            case let .unreadableKey(detail):
                "The App Store Connect private key could not be read: \(detail)"
            }
        }
    }

    /// Apple rejects a token whose lifetime exceeds 20 minutes, so this is the
    /// ceiling rather than a preference. Tokens are minted per refresh and
    /// thrown away; nothing here caches one.
    public static let maximumLifetime: TimeInterval = 20 * 60

    public static func make(
        issuerID: String,
        keyID: String,
        privateKeyPEM: String,
        now: Date,
        lifetime: TimeInterval = maximumLifetime
    ) throws -> String {
        let key: P256.Signing.PrivateKey
        do {
            key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        } catch {
            throw Failure.unreadableKey(error.localizedDescription)
        }

        let header: [String: String] = [
            "alg": "ES256",
            "kid": keyID,
            "typ": "JWT",
        ]
        let payload: [String: Any] = [
            "iss": issuerID,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(min(lifetime, maximumLifetime)).timeIntervalSince1970),
            "aud": "appstoreconnect-v1",
        ]

        let signingInput = "\(try json(header)).\(try json(payload))"
        // rawRepresentation is r‖s, which is what JWS ES256 wants. The DER
        // encoding CryptoKit also offers would be rejected.
        let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation

        return "\(signingInput).\(signature.base64URLEncoded)"
    }

    /// `.sortedKeys` is not for tidiness: it makes the token a pure function of
    /// its inputs, so a test can assert on the exact string.
    private static func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return data.base64URLEncoded
    }
}

extension Data {
    /// base64url per RFC 4648 §5: the two swapped characters, and no padding.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        self.init(base64Encoded: padded)
    }
}
