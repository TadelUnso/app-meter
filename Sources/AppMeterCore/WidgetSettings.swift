import Foundation

/// UserDefaults keys shared by the app shell and the views.
///
/// Key names, defaults and clamps only — no state. Secrets never live here:
/// the App Store Connect .p8 and the Google service account JSON go to the
/// Keychain, and only their non-secret companions (issuer id, key id, vendor
/// number) are stored as plain defaults.
public enum WidgetSettings {
    /// Pins the widget in place: blocks both dragging and resizing.
    public static let positionLockedKey = "positionLocked"

    /// Whether the desktop window is on screen. Polling keeps running while it
    /// is hidden, so bringing it back shows fresh figures.
    public static let widgetVisibleKey = "widgetVisible"

    /// Width of the panel, in points. Unlike the sibling claude-usage-widget the
    /// panel is not a square: the number of apps decides the layout and the
    /// layout decides the height, so only the width is the user's to set.
    public static let widgetWidthKey = "widgetWidth"

    /// The layout is designed at 520 pt and scales linearly from there.
    public static let defaultWidth: Double = 520
    public static let minWidth: Double = 320
    public static let maxWidth: Double = 900

    /// Minutes between polls. Both stores publish reports once a day, so a
    /// faster poll would only spend request quota to re-read the same figures.
    public static let refreshIntervalKey = "refreshIntervalMinutes"
    public static let defaultRefreshInterval: Double = 60

    /// App Store Connect, non-secret half. The private key itself is a Keychain
    /// item; these three only identify it.
    public static let ascIssuerIdKey = "ascIssuerId"
    public static let ascKeyIdKey = "ascKeyId"
    public static let ascVendorNumberKey = "ascVendorNumber"

    /// Google Play, non-secret half: the Cloud Storage bucket the console
    /// exports reports to. The service account JSON is a Keychain item.
    public static let googlePlayBucketKey = "googlePlayBucket"

    /// `bool(forKey:)` returns false for an absent key, which would start a
    /// fresh install hidden with no way to tell why.
    public static func isVisible(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: widgetVisibleKey) as? Bool ?? true
    }

    public static func clampWidth(_ width: Double) -> Double {
        min(max(width, minWidth), maxWidth)
    }

    public static func width(in defaults: UserDefaults) -> Double {
        guard let stored = defaults.object(forKey: widgetWidthKey) as? Double else { return defaultWidth }
        return clampWidth(stored)
    }
}
