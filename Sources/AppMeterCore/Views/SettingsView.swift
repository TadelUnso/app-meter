import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The one place credentials are entered.
///
/// Deliberately a plain system Form rather than the widget's dark glass: this is
/// a standard settings window, and the panel's styling would make it read as
/// part of the widget that has somehow come loose.
///
/// Nothing here is verified against the stores — the checks are shape checks, so
/// a mistyped field is caught at the keyboard rather than as a silent empty
/// panel later. The first refresh is what proves a credential works.
public struct SettingsView: View {
    @AppStorage(WidgetSettings.ascIssuerIdKey) private var ascIssuerID = ""
    @AppStorage(WidgetSettings.ascKeyIdKey) private var ascKeyID = ""
    @AppStorage(WidgetSettings.ascVendorNumberKey) private var ascVendorNumber = ""
    @AppStorage(WidgetSettings.googlePlayBucketKey) private var googlePlayBucket = ""
    @AppStorage(WidgetSettings.googleAnalyticsPropertyKey) private var googleAnalyticsProperty = ""
    @AppStorage(WidgetSettings.googleAnalyticsStreamKey) private var googleAnalyticsStream = ""
    @AppStorage(WidgetSettings.googleAnalyticsPackageKey) private var googleAnalyticsPackage = ""
    @AppStorage(WidgetSettings.refreshIntervalKey) private var refreshInterval = WidgetSettings.defaultRefreshInterval

    /// Mirrors of the keychain, refreshed on appear and after every write. The
    /// secrets themselves are never held here — only whether they are there, and
    /// which account the Google one names.
    @State private var hasAppStoreKey = false
    @State private var serviceAccount: GoogleServiceAccount?
    @State private var problem: String?

    public init() {}

    public var body: some View {
        Form {
            appStoreSection
            googlePlaySection
            googleAnalyticsSection

            Section("Refresh") {
                Picker("Check for new figures", selection: $refreshInterval) {
                    Text("Every 15 minutes").tag(15.0)
                    Text("Every 30 minutes").tag(30.0)
                    Text("Every hour").tag(60.0)
                    Text("Every 6 hours").tag(360.0)
                }
                Text("Both stores publish once a day, so a faster poll only spends request quota re-reading the same figures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        // A grouped Form always scrolls; the height is picked so that it does
        // not have to. Every row is visible at once on the smallest Mac display.
        .frame(width: 480, height: 750)
        .onAppear(perform: reloadKeychainState)
    }

    private var appStoreSection: some View {
        Section("App Store Connect") {
            field(
                "Issuer ID",
                text: $ascIssuerID,
                prompt: "00000000-0000-0000-0000-000000000000",
                isValid: AppStoreConnectCredentials.isValidIssuerID,
                hint: "Users and Access → Integrations → App Store Connect API."
            )
            field(
                "Key ID",
                text: $ascKeyID,
                prompt: "ABCD123456",
                isValid: AppStoreConnectCredentials.isValidKeyID,
                hint: "Ten characters, the same ones as in the AuthKey_….p8 filename."
            )
            field(
                "Vendor number",
                text: $ascVendorNumber,
                prompt: "80000000",
                isValid: AppStoreConnectCredentials.isValidVendorNumber,
                hint: "Digits only. Payments and Financial Reports, top left."
            )

            LabeledContent("Private key") {
                secretRow(
                    status: hasAppStoreKey ? "Stored in Keychain" : "Not set",
                    isSet: hasAppStoreKey,
                    chooseTitle: "Choose .p8…",
                    choose: importPrivateKey,
                    remove: { remove(.appStoreConnectKey) }
                )
            }
        }
    }

    private var googlePlaySection: some View {
        Section("Google Play") {
            LabeledContent("Service account") {
                secretRow(
                    status: serviceAccount?.clientEmail ?? "Not set",
                    isSet: serviceAccount != nil,
                    chooseTitle: "Choose JSON…",
                    choose: importServiceAccount,
                    remove: { remove(.googlePlayServiceAccount) }
                )
            }

            field(
                "Reports bucket",
                text: $googlePlayBucket,
                prompt: "pubsite_prod_0000000000000000000",
                isValid: { GooglePlayCredentials.bucketName(from: $0) != nil },
                hint: "Play Console → Download reports → Copy Cloud Storage URI. Paste it exactly as copied."
            )
        }
    }

    private var googleAnalyticsSection: some View {
        Section("Google Analytics (optional)") {
            field(
                "GA4 property ID",
                text: $googleAnalyticsProperty,
                prompt: "123456789",
                isValid: GoogleAnalyticsCredentials.isValidPropertyID,
                hint: "Analytics Admin → Property details. Grant the service account above Viewer access to this property."
            )
            field(
                "Data stream ID",
                text: $googleAnalyticsStream,
                prompt: "9876543210",
                isValid: GoogleAnalyticsCredentials.isValidStreamID,
                hint: "Analytics Admin → Data streams → your Android app. This keeps other Android apps out of the count."
            )
            field(
                "Android package",
                text: $googleAnalyticsPackage,
                prompt: "com.example.app",
                isValid: GoogleAnalyticsCredentials.isValidPackageName,
                hint: "The package name shown for the same app in Play Console."
            )
            Text("Adds Firebase first_open events only after Play's newest confirmed report day, so delayed Play reports are not deliberately counted twice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A text field with its hint underneath, and the hint turning red once what
    /// is typed cannot be right. Silent while the field is still empty: a fresh
    /// install would otherwise open covered in errors for fields nobody has
    /// reached yet.
    private func field(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        isValid: (String) -> Bool,
        hint: String
    ) -> some View {
        let entered = text.wrappedValue
        let malformed = !entered.isEmpty && !isValid(entered)

        return VStack(alignment: .leading, spacing: 3) {
            TextField(label, text: text, prompt: Text(prompt))
            Text(malformed ? "That does not look like a \(label.lowercased()). \(hint)" : hint)
                .font(.caption)
                .foregroundStyle(malformed ? Color.red : Color.secondary)
        }
    }

    private func secretRow(
        status: String,
        isSet: Bool,
        chooseTitle: String,
        choose: @escaping () -> Void,
        remove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button(isSet ? "Replace…" : chooseTitle, action: choose)
            if isSet {
                Button("Remove", action: remove)
            }
        }
    }

    private func importPrivateKey() {
        guard let text = readFile(named: "private key", types: [UTType(filenameExtension: "p8") ?? .data]) else { return }
        guard let pem = AppStoreConnectCredentials.privateKey(fromPEM: text) else {
            problem = "That file is not an App Store Connect private key — expected the .p8 downloaded from Users and Access."
            return
        }
        write(pem, to: .appStoreConnectKey)
    }

    private func importServiceAccount() {
        guard let text = readFile(named: "service account", types: [.json]) else { return }
        guard GoogleServiceAccount(json: text) != nil else {
            problem = "That file is not a Google service account key — expected the JSON downloaded from the service account's Keys tab."
            return
        }
        write(text, to: .googlePlayServiceAccount)
    }

    /// The panel is modal to the settings window, so a file chosen here cannot
    /// race a second import.
    private func readFile(named what: String, types: [UTType]) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose your \(what) file. It is copied into the Keychain, not referenced in place."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            problem = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    private func write(_ value: String, to secret: KeychainStore.Secret) {
        do {
            try KeychainStore.save(value, for: secret)
            problem = nil
        } catch {
            problem = "Could not write to the Keychain: \(error.localizedDescription)"
        }
        reloadKeychainState()
    }

    private func remove(_ secret: KeychainStore.Secret) {
        do {
            try KeychainStore.delete(secret)
            problem = nil
        } catch {
            problem = "Could not remove the key from the Keychain: \(error.localizedDescription)"
        }
        reloadKeychainState()
    }

    private func reloadKeychainState() {
        hasAppStoreKey = KeychainStore.contains(.appStoreConnectKey)
        serviceAccount = KeychainStore.load(.googlePlayServiceAccount).flatMap(GoogleServiceAccount.init(json:))
    }
}
