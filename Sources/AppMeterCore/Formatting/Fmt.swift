import Foundation

/// Number formatting for the panel.
///
/// Hand-rolled rather than `NumberFormatter`-driven so the output does not
/// change with the user's locale: the design groups thousands with a narrow
/// space regardless of where the machine thinks it is, and a locale that used
/// a comma or a dot would read as a decimal point next to figures this large.
public enum Fmt {
    /// U+202F NARROW NO-BREAK SPACE. A plain space would let a line break fall
    /// inside a number.
    public static let groupSeparator = "\u{202F}"

    /// "214 900". Negative totals cannot occur, but are rendered rather than
    /// trapped — a wrong figure on screen beats a crash.
    public static func installs(_ value: Int) -> String {
        grouped(value)
    }

    /// The day's change: "+1 284", or an em dash when nothing moved. Zero is
    /// shown as a dash on purpose — "+0" reads like a measurement, a dash reads
    /// like the non-event it is.
    public static func delta(_ value: Int) -> String {
        switch value {
        case 0: "—"
        case let v where v > 0: "+" + grouped(v)
        default: grouped(value)
        }
    }

    private static func grouped(_ value: Int) -> String {
        let negative = value < 0
        // Built from the magnitude so Int.min does not overflow on negation.
        var digits = Array(String(value.magnitude))
        var out: [String] = []
        while digits.count > 3 {
            out.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        out.insert(String(digits), at: 0)
        return (negative ? "-" : "") + out.joined(separator: groupSeparator)
    }
}
