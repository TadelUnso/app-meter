import Testing
@testable import AppMeterCore

@Suite("App Store Connect credentials")
struct AppStoreConnectCredentialsTests {
    @Test("accepts a UUID issuer id, with or without stray whitespace")
    func issuerID() {
        #expect(AppStoreConnectCredentials.isValidIssuerID("69a6de70-03db-47e3-e053-5b8c7c11a4d1"))
        #expect(AppStoreConnectCredentials.isValidIssuerID("  69a6de70-03db-47e3-e053-5b8c7c11a4d1\n"))
        #expect(!AppStoreConnectCredentials.isValidIssuerID(""))
        #expect(!AppStoreConnectCredentials.isValidIssuerID("ABCD123456"))
    }

    /// The one confusion the field checks exist to catch: the two ids are
    /// pasted from the same page and are easy to swap.
    @Test("rejects an issuer id typed into the key id box")
    func keyID() {
        #expect(AppStoreConnectCredentials.isValidKeyID("ABCD123456"))
        #expect(!AppStoreConnectCredentials.isValidKeyID("69a6de70-03db-47e3-e053-5b8c7c11a4d1"))
        #expect(!AppStoreConnectCredentials.isValidKeyID("ABCD12345"))
        #expect(!AppStoreConnectCredentials.isValidKeyID("ABCD1234567"))
    }

    @Test("takes digits of any length as a vendor number")
    func vendorNumber() {
        #expect(AppStoreConnectCredentials.isValidVendorNumber("85000000"))
        #expect(AppStoreConnectCredentials.isValidVendorNumber("123456789"))
        #expect(!AppStoreConnectCredentials.isValidVendorNumber(""))
        #expect(!AppStoreConnectCredentials.isValidVendorNumber("85-000000"))
    }

    @Test("takes a .p8 and hands back the trimmed PEM")
    func privateKey() {
        let pem = """
        -----BEGIN PRIVATE KEY-----
        MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg
        -----END PRIVATE KEY-----
        """
        #expect(AppStoreConnectCredentials.privateKey(fromPEM: "\n\(pem)\n\n") == pem)
    }

    @Test("rejects a file that is not a private key")
    func privateKeyRejectsOtherFiles() {
        #expect(AppStoreConnectCredentials.privateKey(fromPEM: "") == nil)
        #expect(AppStoreConnectCredentials.privateKey(fromPEM: "-----BEGIN CERTIFICATE-----") == nil)
        // Truncated: the header arrived, the key did not.
        #expect(AppStoreConnectCredentials.privateKey(fromPEM: "-----BEGIN PRIVATE KEY-----") == nil)
    }
}

@Suite("Google service account")
struct GoogleServiceAccountTests {
    private static func json(
        type: String = "service_account",
        email: String = "app-meter@example.iam.gserviceaccount.com",
        key: String = "-----BEGIN PRIVATE KEY-----\\nMIIE\\n-----END PRIVATE KEY-----\\n"
    ) -> String {
        """
        {
          "type": "\(type)",
          "project_id": "example-project",
          "client_email": "\(email)",
          "private_key": "\(key)"
        }
        """
    }

    @Test func readsTheAccountItNames() {
        let account = GoogleServiceAccount(json: Self.json())
        #expect(account?.clientEmail == "app-meter@example.iam.gserviceaccount.com")
        #expect(account?.projectID == "example-project")
    }

    /// The OAuth client JSON sits next to the service account key in the Cloud
    /// console and downloads under a similar name.
    @Test func rejectsAnotherKindOfCredential() {
        #expect(GoogleServiceAccount(json: Self.json(type: "authorized_user")) == nil)
    }

    @Test func rejectsAnIncompleteFile() {
        #expect(GoogleServiceAccount(json: Self.json(email: "")) == nil)
        #expect(GoogleServiceAccount(json: Self.json(key: "")) == nil)
        #expect(GoogleServiceAccount(json: "not json at all") == nil)
    }
}

@Suite("Google Play bucket")
struct GooglePlayCredentialsTests {
    private static let bucket = "pubsite_prod_1234567890123456789"

    @Test("takes the console's gs:// URI as readily as the bare name")
    func normalises() {
        #expect(GooglePlayCredentials.bucketName(from: Self.bucket) == Self.bucket)
        #expect(GooglePlayCredentials.bucketName(from: "gs://\(Self.bucket)") == Self.bucket)
        #expect(GooglePlayCredentials.bucketName(from: " gs://\(Self.bucket)/ ") == Self.bucket)
    }

    /// What Copy Cloud Storage URI actually puts on the clipboard, verbatim —
    /// the bucket with the section's own path already attached.
    @Test func dropsThePathTheConsoleCopiesAlongWithIt() {
        #expect(GooglePlayCredentials.bucketName(from: "gs://\(Self.bucket)/stats/installs/") == Self.bucket)
    }

    /// Older accounts have a `_rev` in the name; both forms are real.
    @Test func acceptsTheOlderRevNaming() {
        #expect(GooglePlayCredentials.bucketName(from: "gs://pubsite_prod_rev_01234567890987654321")
            == "pubsite_prod_rev_01234567890987654321")
    }

    /// A paste that lost its scheme on the way — the leading slash is all that
    /// survives of `gs://`, and the bucket after it is still the bucket.
    @Test func survivesAPasteThatLostItsScheme() {
        #expect(GooglePlayCredentials.bucketName(from: "/\(Self.bucket)/stats/installs/") == Self.bucket)
    }

    @Test func rejectsAnythingUnrelated() {
        #expect(GooglePlayCredentials.bucketName(from: "") == nil)
        #expect(GooglePlayCredentials.bucketName(from: "my-bucket") == nil)
        #expect(GooglePlayCredentials.bucketName(from: "gs:///stats/installs") == nil)
    }
}
