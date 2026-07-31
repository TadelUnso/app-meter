import SwiftUI

/// The widget palette: a dark glass panel, in the spirit of the sibling
/// mole-widget and claude-usage-widget.
public enum Theme {
    public static let panel = Color(red: 0.118, green: 0.133, blue: 0.188)
    public static let track = Color(red: 0.250, green: 0.270, blue: 0.340)
    public static let text = Color(red: 0.780, green: 0.800, blue: 0.870)
    public static let dim = Color(red: 0.450, green: 0.470, blue: 0.550)

    public static let accent = Color(red: 0.651, green: 0.820, blue: 0.537)
    public static let warning = Color(red: 0.898, green: 0.784, blue: 0.565)
    public static let danger = Color(red: 0.906, green: 0.510, blue: 0.518)

    /// The two stores get a colour each, used only for the dot beside their
    /// label. Deliberately not the stores' own brand colours — these are picked
    /// to sit in the same pastel family as the rest of the panel.
    public static let appStore = Color(red: 0.706, green: 0.616, blue: 0.902)
    public static let googlePlay = Color(red: 0.651, green: 0.820, blue: 0.537)

    /// Fonts are defined at the 520 pt design width and scale with the panel.
    /// Monospaced digits everywhere, so figures do not jitter as they change.
    public static func label(scale: Double) -> Font {
        .system(size: 9 * scale, weight: .semibold).monospacedDigit()
    }

    public static func value(scale: Double) -> Font {
        .system(size: 34 * scale, weight: .regular).monospacedDigit()
    }

    public static func delta(scale: Double) -> Font {
        .system(size: 12 * scale, weight: .medium).monospacedDigit()
    }

    public static func title(scale: Double) -> Font {
        .system(size: 13 * scale, weight: .medium)
    }

    public static func caption(scale: Double) -> Font {
        .system(size: 10 * scale, weight: .medium).monospacedDigit()
    }
}
