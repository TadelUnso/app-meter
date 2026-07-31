import Foundation
import Security

/// The two store secrets, kept in the login keychain.
///
/// Everything else the stores need — issuer id, key id, vendor number, bucket —
/// is a plain default; only the key material lives here. Splitting them that way
/// keeps the defaults plist readable and shareable while the secrets stay behind
/// the keychain prompt.
public enum KeychainStore {
    public enum Secret: String, CaseIterable, Sendable {
        /// The App Store Connect .p8 private key, PEM text exactly as downloaded.
        case appStoreConnectKey = "AppStoreConnectPrivateKey"
        /// The Google service account JSON, verbatim.
        case googlePlayServiceAccount = "GooglePlayServiceAccount"
    }

    public enum Failure: LocalizedError {
        case keychain(OSStatus)

        public var errorDescription: String? {
            switch self {
            case let .keychain(status):
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            }
        }
    }

    private static let service = "com.sbezbabnykh.app-meter"

    private static func query(for secret: Secret) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secret.rawValue,
        ]
    }

    /// Writes, replacing whatever was stored before.
    ///
    /// `AfterFirstUnlock` rather than `WhenUnlocked`: the widget keeps polling
    /// while the screen is locked, and a refresh that fails for the length of a
    /// lunch break would look like a broken credential.
    public static func save(_ value: String, for secret: Secret) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            query(for: secret) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query(for: secret)
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Failure.keychain(addStatus) }
        default:
            throw Failure.keychain(status)
        }
    }

    public static func load(_ secret: Secret) -> String? {
        var lookup = query(for: secret)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    /// Presence check that never pulls the secret into memory — the Settings
    /// form only needs to know whether a key is there.
    public static func contains(_ secret: Secret) -> Bool {
        SecItemCopyMatching(query(for: secret) as CFDictionary, nil) == errSecSuccess
    }

    /// Removing an absent item is a success: the caller wanted it gone.
    public static func delete(_ secret: Secret) throws {
        let status = SecItemDelete(query(for: secret) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychain(status)
        }
    }
}
