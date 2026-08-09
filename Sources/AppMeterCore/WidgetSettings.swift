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

    /// Width of the panel, in points. Unlike the sibling claude-usage-widget the
    /// panel is not a square: the number of apps decides the layout and the
    /// layout decides the height, so only the width is the user's to set.
    public static let widgetWidthKey = "widgetWidth"

    /// The layout is designed at 520 pt and scales linearly above it. Below it
    /// the type stays at its design size and the panel simply gets tighter —
    /// see `scale(forWidth:)`.
    public static let defaultWidth: Double = 520
    /// The narrowest the panel goes. Set by what the composition needs at its
    /// design size rather than by how far it can be shrunk: since a narrow
    /// panel no longer shrinks its type, going below this only truncates.
    public static let minWidth: Double = 350
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

    public static func clampWidth(_ width: Double) -> Double {
        min(max(width, minWidth), maxWidth)
    }

    /// The multiplier every font, padding and glyph in the panel is drawn at.
    ///
    /// Floored at 1: a panel narrower than the design width keeps its type,
    /// spacing and controls at full size and gives up horizontal room instead.
    /// Scaling both together made a narrow panel a zoomed-out one — the Ko-fi
    /// capsule, the captions and the icons all shrank along with it, when the
    /// only thing the user was asking for was less width. Above the design
    /// width scaling resumes, so a panel dragged wide still grows its figures.
    ///
    /// Lives here beside the clamp so the view and its tests cannot disagree
    /// about it.
    public static func scale(forWidth width: Double) -> Double {
        max(1, clampWidth(width) / defaultWidth)
    }

    public static func width(in defaults: UserDefaults) -> Double {
        guard let stored = defaults.object(forKey: widgetWidthKey) as? Double else { return defaultWidth }
        return clampWidth(stored)
    }
}
