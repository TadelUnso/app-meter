import Foundation

/// Assembles store accounts out of the two halves they are stored in: the plain
/// preferences and the Keychain.
///
/// Returns nil rather than a half-filled account — a request built from three
/// of the four fields fails at the far end with an error that says nothing
/// about which field is missing.
public enum StoreAccounts {
    public struct GoogleAnalytics: Sendable {
        public let package: String
        public let client: GoogleAnalyticsClient
    }

    public static func appStoreConnect(defaults: UserDefaults = .standard) -> AppStoreConnectAccount? {
        guard let issuerID = defaults.string(forKey: WidgetSettings.ascIssuerIdKey), !issuerID.isEmpty,
              let keyID = defaults.string(forKey: WidgetSettings.ascKeyIdKey), !keyID.isEmpty,
              let vendorNumber = defaults.string(forKey: WidgetSettings.ascVendorNumberKey), !vendorNumber.isEmpty,
              let pem = KeychainStore.load(.appStoreConnectKey)
        else { return nil }

        return AppStoreConnectAccount(
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            vendorNumber: vendorNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: pem
        )
    }

    /// The Play client, or nil while either half — the JSON in the Keychain or
    /// the bucket in defaults — is missing.
    public static func googlePlay(defaults: UserDefaults = .standard) -> GooglePlayClient? {
        guard let json = KeychainStore.load(.googlePlayServiceAccount),
              let account = GoogleServiceAccount(json: json),
              let stored = defaults.string(forKey: WidgetSettings.googlePlayBucketKey),
              let bucket = GooglePlayCredentials.bucketName(from: stored)
        else { return nil }

        // The signing key stays inside the JSON; pulling it out here keeps
        // GoogleServiceAccount itself free of secret material.
        struct KeyOnly: Decodable { let private_key: String }
        guard let pem = (try? JSONDecoder().decode(KeyOnly.self, from: Data(json.utf8)))?.private_key else {
            return nil
        }

        return GooglePlayClient(account: account, privateKeyPEM: pem, bucket: bucket)
    }

    /// The optional GA4 first-open source. It reuses the Play service account,
    /// but GA4 must separately grant that email Viewer access to the property.
    public static func googleAnalytics(defaults: UserDefaults = .standard) -> GoogleAnalytics? {
        guard let json = KeychainStore.load(.googlePlayServiceAccount),
              let account = GoogleServiceAccount(json: json),
              let property = defaults.string(forKey: WidgetSettings.googleAnalyticsPropertyKey),
              GoogleAnalyticsCredentials.isValidPropertyID(property),
              let stream = defaults.string(forKey: WidgetSettings.googleAnalyticsStreamKey),
              GoogleAnalyticsCredentials.isValidStreamID(stream),
              let package = defaults.string(forKey: WidgetSettings.googleAnalyticsPackageKey),
              GoogleAnalyticsCredentials.isValidPackageName(package)
        else { return nil }

        struct KeyOnly: Decodable { let private_key: String }
        guard let pem = (try? JSONDecoder().decode(KeyOnly.self, from: Data(json.utf8)))?.private_key else {
            return nil
        }

        return GoogleAnalytics(
            package: package.trimmingCharacters(in: .whitespacesAndNewlines),
            client: GoogleAnalyticsClient(
                account: account,
                privateKeyPEM: pem,
                propertyID: property.trimmingCharacters(in: .whitespacesAndNewlines),
                streamID: stream.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }
}

/// Prints one real sales report to the log.
///
/// Set `APP_METER_DUMP_SALES=1` to run it at launch. It exists because the
/// product type identifiers in `SalesReport.firstDownloadTypes` are a claim
/// about what Apple sends, and the only way to check a claim like that is to
/// look at a real account's report.
public enum SalesDump {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["APP_METER_DUMP_SALES"] == "1"
    }

    public static func run() async {
        if let account = StoreAccounts.appStoreConnect() {
            let client = AppStoreConnectClient(account: account)
            do {
                let figures = try await AppleInstallsService(client: client).installs().figures
                dump(figures, from: "apple")
            } catch {
                NSLog("[sales] apple failed: %@", error.localizedDescription)
            }
        } else {
            NSLog("[sales] no App Store Connect account configured")
        }

        if let client = StoreAccounts.googlePlay() {
            do {
                let figures = try await PlayInstallsService(client: client).figures()
                dump(figures, from: "google")
            } catch {
                NSLog("[sales] google failed: %@", error.localizedDescription)
            }

            // Separates "the bucket refuses listing" from "the bucket refuses
            // everything": the two need different fixes, and the error body of
            // the listing alone cannot tell them apart.
            if let probe = ProcessInfo.processInfo.environment["APP_METER_PROBE_PACKAGE"] {
                await probeDirectFetch(client: client, package: probe)
            }
        } else {
            NSLog("[sales] no Google Play account configured")
        }
    }

    private static func probeDirectFetch(client: GooglePlayClient, package: String) async {
        let calendar = SalesPeriods.calendar
        let parts = calendar.dateComponents([.year, .month], from: Date())
        guard let year = parts.year, let month = parts.month else { return }

        for offset in 0...1 {
            var target = (year: year, month: month - offset)
            if target.month < 1 { target = (year - 1, 12) }

            do {
                if let report = try await client.installsReport(
                    package: package, year: target.year, month: target.month
                ) {
                    NSLog("[probe] %04d-%02d direct GET worked: %d day(s), %d install(s)",
                          target.year, target.month, report.days.count, report.userInstalls)
                } else {
                    NSLog("[probe] %04d-%02d: no file (404)", target.year, target.month)
                }
            } catch {
                NSLog("[probe] %04d-%02d failed: %@", target.year, target.month, error.localizedDescription)
            }
        }
    }

    private static func dump(_ figures: [AppFigures], from store: String) {
        NSLog("[sales] %@: %d app(s)", store, figures.count)
        for app in figures {
            NSLog("[sales] %@ %@ (%@): %d lifetime, %d on %@",
                  store, app.name, app.id, app.lifetime, app.today,
                  app.asOf.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown day")
        }
    }
}
