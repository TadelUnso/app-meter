import CryptoKit
import Foundation
import Testing
@testable import AppMeterCore

@Suite("App Store Connect token")
struct AppStoreConnectTokenTests {
    /// A throwaway P-256 key generated for the tests. Nothing signed with it
    /// ever leaves the process.
    private static let key = P256.Signing.PrivateKey()

    private static func token(now: Date = Date(timeIntervalSince1970: 1_700_000_000),
                              lifetime: TimeInterval = AppStoreConnectToken.maximumLifetime) throws -> String {
        try AppStoreConnectToken.make(
            issuerID: "69a6de70-03db-47e3-e053-5b8c7c11a4d1",
            keyID: "ABCD123456",
            privateKeyPEM: key.pemRepresentation,
            now: now,
            lifetime: lifetime
        )
    }

    private static func segment(_ token: String, _ index: Int) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        let data = try #require(Data(base64URLEncoded: String(parts[index])))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func headerNamesTheAlgorithmAndKey() throws {
        let header = try Self.segment(try Self.token(), 0)
        #expect(header["alg"] as? String == "ES256")
        #expect(header["typ"] as? String == "JWT")
        #expect(header["kid"] as? String == "ABCD123456")
    }

    @Test func payloadCarriesIssuerAndAudience() throws {
        let payload = try Self.segment(try Self.token(), 1)
        #expect(payload["iss"] as? String == "69a6de70-03db-47e3-e053-5b8c7c11a4d1")
        #expect(payload["aud"] as? String == "appstoreconnect-v1")
        #expect(payload["iat"] as? Int == 1_700_000_000)
        #expect(payload["exp"] as? Int == 1_700_000_000 + 1200)
    }

    /// Apple rejects anything longer, so a caller asking for a day gets twenty
    /// minutes rather than a token that fails at the far end.
    @Test func clampsAnOverlongLifetime() throws {
        let payload = try Self.segment(try Self.token(lifetime: 86_400), 1)
        #expect(payload["exp"] as? Int == 1_700_000_000 + 1200)
    }

    /// The point of the whole file: a signature Apple's side will accept.
    @Test func signatureVerifiesOverHeaderAndPayload() throws {
        let token = try Self.token()
        let parts = token.split(separator: ".")
        #expect(parts.count == 3)

        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        let raw = try #require(Data(base64URLEncoded: String(parts[2])))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: raw)

        #expect(Self.key.publicKey.isValidSignature(signature, for: signingInput))
    }

    /// ES256 signatures are r‖s — 64 bytes flat. A DER-encoded one would be
    /// variable-length and silently rejected by Apple.
    @Test func signatureIsRawNotDER() throws {
        let parts = try Self.token().split(separator: ".")
        let raw = try #require(Data(base64URLEncoded: String(parts[2])))
        #expect(raw.count == 64)
    }

    @Test func base64URLHasNoPaddingOrSlashes() throws {
        let token = try Self.token()
        #expect(!token.contains("="))
        #expect(!token.contains("/"))
        #expect(!token.contains("+"))
    }

    @Test func rejectsSomethingThatIsNotAKey() {
        #expect(throws: AppStoreConnectToken.Failure.self) {
            try AppStoreConnectToken.make(
                issuerID: "irrelevant",
                keyID: "irrelevant",
                privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nnonsense\n-----END PRIVATE KEY-----",
                now: Date()
            )
        }
    }
}
