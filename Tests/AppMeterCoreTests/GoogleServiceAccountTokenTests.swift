import Foundation
import Security
import Testing
@testable import AppMeterCore

@Suite("Google service account token")
struct GoogleServiceAccountTokenTests {
    /// A throwaway 2048-bit RSA key, generated for these tests and used
    /// nowhere else. Real PKCS#8 armour, which is the point: the wrapper this
    /// suite peels has to be the one Google actually ships.
    private static let pem = """
    -----BEGIN PRIVATE KEY-----
    MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCUX+dzqUqkzsCr
    Hq0GNDc3HTH+uUiCF145r+PSPj3SJAyw4xxgo3y2UpGAFWYh2zoE4H6XoGQu5zwP
    fUxsbpqZjx7/FAGeCz99BKt/FynzO4RGX9yPcuViDOXjZezK905f6XZXx5BZigaA
    X08uItFIGGjkMyaK1QdxDnJ2kujMnixYlK0Bz/YIhUpjH8nO4TiFiz87rTKrPN6Q
    c/U/vnGom/gFdTI86CQxrGV/zGoci4toCVSQCR7vsrB3RdZ++QAhqcObndAnFrLT
    jH8NRz2s+uI39yX/PZEhJFXmY5Nj0OoSg5ZThlfzhLPYsku3S4kGNIAk6ntKw/MB
    4lby7MHLAgMBAAECggEALEWthyp1dlWm0ah2kkpUS2Kvv0TD6OVWHTppbRtbUO+m
    xcUOe5tso+5hMemwrtt+JWRjAZU/L2uZ1Tla62PZR4aYBh6PGPxcNk6FaYec4dHZ
    dzI1Wqw625XjpoWMMUe3oBDGWgzW+pCfvgAyXR7QeYWnDqhgkL5d2RMpfk35nswD
    LaLoODJkzuTJCxcBRyCgbKpQsyflrxgk6fstMTKBcgy/ohye+nPvuPfrEARP04iV
    nuaIOi1b88HjfsipODysJ01qAV91OwAJpH79HpqBrm9+BX9BFvXTD03fZXcS6SqN
    DWwnr22kfeCy01/ht6hUJaiUEYcZNOOkTPteq1WEAQKBgQDIwgL70tNUEfbNjhaM
    Jnk2G5C6z0uOHqi8SucUMcj/bN36Iofs74rzqU6nhBD+KoeeE3tN/UEJH4sdV0QJ
    4MmRJuRmWfppcizqOyz1EgevXDyLthI+C6xyIqLRYST33FA7Uma6HHwqdSJJ+h2z
    pzJR8o0kT8mtmUyVRZ06gIx3ywKBgQC9M9wXfZQwu5yj3zvLaJMPNqNTFtknuVBV
    gmJh7uxdlMX+omw6kP6kXZas+oXXUnQT+4TcMAbAYLydmjLxpDISpag4FHehD8a6
    1Ev8U3ZTe+PdWQUC4/aUB03dBrYPgHdzTaPNwSy2q6AaglfWDl6uFvuGsSavWQli
    QcDDSTOeAQKBgDjCaZeLHsaZIZ8yOfu78O80UfIPI7x1vJ0nzDdwb/SPch8DXkzF
    2RJU3vELrMY/fgJaXbVKEfYjXfCYuJrWXAbW6SJq9BqV9k7vFiHfzB5vRIr3mibC
    pCnM0x3BinMtbd2nyXV7EjvqzBwARB+D+P0kR3VpvYqAWh+mA/MDXzOLAoGAXFYi
    45P17pKhL5iSpgKzQol3y+UqtahK/HBVc1YXJNSmjE7YYvzASZcjIehhyWQEInxt
    qsgFg32yj3fhxOxNQ6x1HGlguMnqQuO48bwJ01RzMGNxfqeifzvRVD0iPQ6FPVB2
    0MOl/sBjsoxKMb1xl6S/vExYhNr/KWTNnoDrIAECgYA6AkGymkrqERlgC1YkFZxC
    JpzGDxJ/vJVGS//rfL3NXIiKGTGqS3gu2bGq0TkNjpWaH9rmxB+On7GXeC+zzt/O
    1p71Bmpj31Uhx72gaL1dyNBSu7g6gGtnhxHhVx7j4cOwlpQcgGN6oP0TSfuIphjG
    gdqrQNt4xhav89xGkG5knw==
    -----END PRIVATE KEY-----
    """

    private static let email = "app-meter-reports@example.iam.gserviceaccount.com"

    private static func token(now: Date = Date(timeIntervalSince1970: 1_700_000_000),
                              lifetime: TimeInterval = GoogleServiceAccountToken.maximumLifetime) throws -> String {
        try GoogleServiceAccountToken.make(clientEmail: email, privateKeyPEM: pem, now: now, lifetime: lifetime)
    }

    private static func segment(_ token: String, _ index: Int) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        let data = try #require(Data(base64URLEncoded: String(parts[index])))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func headerNamesRS256() throws {
        let header = try Self.segment(try Self.token(), 0)
        #expect(header["alg"] as? String == "RS256")
        #expect(header["typ"] as? String == "JWT")
    }

    @Test func payloadAsksForReadOnlyStorage() throws {
        let payload = try Self.segment(try Self.token(), 1)
        #expect(payload["iss"] as? String == Self.email)
        #expect(payload["aud"] as? String == "https://oauth2.googleapis.com/token")
        #expect(payload["scope"] as? String == "https://www.googleapis.com/auth/devstorage.read_only")
        #expect(payload["exp"] as? Int == 1_700_000_000 + 3600)
    }

    @Test func payloadCanAskForAnalyticsReadOnly() throws {
        let token = try GoogleServiceAccountToken.make(
            clientEmail: Self.email,
            privateKeyPEM: Self.pem,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            scope: GoogleAnalyticsClient.scope
        )
        let payload = try Self.segment(token, 1)
        #expect(payload["scope"] as? String == GoogleAnalyticsClient.scope)
    }

    @Test func clampsAnOverlongLifetime() throws {
        let payload = try Self.segment(try Self.token(lifetime: 86_400), 1)
        #expect(payload["exp"] as? Int == 1_700_000_000 + 3600)
    }

    /// What the whole file is for: a PKCS#1 key correctly dug out of its PKCS#8
    /// wrapper produces a signature the matching public key accepts. A wrong
    /// byte offset would either fail to load the key or sign with garbage.
    @Test func signatureVerifiesWithTheMatchingPublicKey() throws {
        let token = try Self.token()
        let parts = token.split(separator: ".")
        #expect(parts.count == 3)

        let key = try GoogleServiceAccountToken.secKey(fromPEM: Self.pem)
        let publicKey = try #require(SecKeyCopyPublicKey(key))
        let signature = try #require(Data(base64URLEncoded: String(parts[2])))

        var error: Unmanaged<CFError>?
        let valid = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data("\(parts[0]).\(parts[1])".utf8) as CFData,
            signature as CFData,
            &error
        )
        #expect(valid)
    }

    /// A 2048-bit RSA signature is 256 bytes, every time.
    @Test func signatureIsTheKeysWidth() throws {
        let parts = try Self.token().split(separator: ".")
        #expect(try #require(Data(base64URLEncoded: String(parts[2]))).count == 256)
    }

    /// Inside the JSON file the key is one line with literal backslash-n, and
    /// it reaches this code that way when the file is read as raw text.
    @Test func acceptsTheEscapedFormFromTheJSONFile() throws {
        let escaped = Self.pem.replacingOccurrences(of: "\n", with: "\\n")
        let token = try GoogleServiceAccountToken.make(
            clientEmail: Self.email,
            privateKeyPEM: escaped,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(token == (try Self.token()))
    }

    @Test func rejectsSomethingThatIsNotAKey() {
        #expect(throws: GoogleServiceAccountToken.Failure.self) {
            try GoogleServiceAccountToken.make(
                clientEmail: Self.email,
                privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nbm90IGEga2V5\n-----END PRIVATE KEY-----",
                now: Date()
            )
        }
    }
}
