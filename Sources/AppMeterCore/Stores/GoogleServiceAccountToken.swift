import Foundation
import Security

/// Mints the assertion Google exchanges for an access token: an RS256 JWT
/// signed with the service account's RSA key.
///
/// Apple's side of App Meter gets to use CryptoKit, which has no RSA — so this
/// half goes through Security.framework instead. The two token files look
/// alike on purpose; only the algorithm and the key handling differ.
public enum GoogleServiceAccountToken {
    public enum Failure: LocalizedError {
        case notAPrivateKey
        case unusableKey(String)
        case signingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notAPrivateKey:
                "The service account key does not contain a PKCS#8 private key."
            case let .unusableKey(detail):
                "The service account key could not be loaded: \(detail)"
            case let .signingFailed(detail):
                "The service account assertion could not be signed: \(detail)"
            }
        }
    }

    /// Read-only access to Cloud Storage — the reports and nothing else. Play
    /// grants the bucket itself; this only says what the token may do there.
    public static let scope = "https://www.googleapis.com/auth/devstorage.read_only"
    public static let audience = "https://oauth2.googleapis.com/token"

    /// Google's ceiling for an assertion, and there is no reason to ask for
    /// less: the token it buys is what actually gets used.
    public static let maximumLifetime: TimeInterval = 60 * 60

    public static func make(
        clientEmail: String,
        privateKeyPEM: String,
        now: Date,
        lifetime: TimeInterval = maximumLifetime
    ) throws -> String {
        let key = try secKey(fromPEM: privateKeyPEM)

        let header: [String: String] = ["alg": "RS256", "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": clientEmail,
            "scope": scope,
            "aud": audience,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(min(lifetime, maximumLifetime)).timeIntervalSince1970),
        ]

        let signingInput = "\(try json(header)).\(try json(payload))"

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &error
        ) as Data? else {
            throw Failure.signingFailed(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }

        return "\(signingInput).\(signature.base64URLEncoded)"
    }

    private static func json(_ value: Any) throws -> String {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).base64URLEncoded
    }

    /// Google ships the key as PKCS#8, and SecKeyCreateWithData only takes the
    /// PKCS#1 structure inside it — so the wrapper is peeled off here.
    static func secKey(fromPEM pem: String) throws -> SecKey {
        let der = try pkcs1(from: try base64Body(of: pem))

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            der as CFData,
            [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            ] as CFDictionary,
            &error
        ) else {
            throw Failure.unusableKey(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        return key
    }

    /// The JSON file stores the key with literal `\n` escapes, which JSON
    /// decoding turns back into newlines — either way the armour and the line
    /// breaks come out here.
    private static func base64Body(of pem: String) throws -> Data {
        let body = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\\n", with: "")
            .filter { !$0.isWhitespace }

        guard !body.isEmpty, let data = Data(base64Encoded: body) else { throw Failure.notAPrivateKey }
        return data
    }

    /// PKCS#8 is `SEQUENCE { INTEGER version, SEQUENCE algorithm, OCTET STRING
    /// key }`, and the key inside that octet string is the PKCS#1 RSAPrivateKey
    /// Security.framework wants. Walking three fields is less machinery than
    /// pulling in an ASN.1 parser for the one shape that ever appears here.
    private static func pkcs1(from der: Data) throws -> Data {
        var reader = DERReader(der)

        guard let outer = try? reader.readSequenceBody() else { throw Failure.notAPrivateKey }
        var body = DERReader(outer)

        guard (try? body.skipField()) != nil,          // version
              (try? body.skipField()) != nil,          // algorithm identifier
              let key = try? body.readField(tag: 0x04) // OCTET STRING
        else { throw Failure.notAPrivateKey }

        return key
    }
}

/// The smallest DER reader that gets a PKCS#1 key out of a PKCS#8 wrapper.
/// Not a general parser: it reads a tag, a length, and the bytes they describe.
private struct DERReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        self.bytes = [UInt8](data)
    }

    enum Failure: Error { case malformed }

    mutating func readSequenceBody() throws -> Data {
        try readField(tag: 0x30)
    }

    mutating func readField(tag expected: UInt8) throws -> Data {
        guard index < bytes.count, bytes[index] == expected else { throw Failure.malformed }
        index += 1
        let length = try readLength()
        guard index + length <= bytes.count else { throw Failure.malformed }
        defer { index += length }
        return Data(bytes[index..<(index + length)])
    }

    mutating func skipField() throws {
        guard index < bytes.count else { throw Failure.malformed }
        index += 1
        let length = try readLength()
        guard index + length <= bytes.count else { throw Failure.malformed }
        index += length
    }

    /// Short form is one byte; long form says how many bytes carry the length.
    private mutating func readLength() throws -> Int {
        guard index < bytes.count else { throw Failure.malformed }
        let first = bytes[index]
        index += 1

        guard first & 0x80 != 0 else { return Int(first) }

        let count = Int(first & 0x7F)
        guard count > 0, count <= 4, index + count <= bytes.count else { throw Failure.malformed }

        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }
}
