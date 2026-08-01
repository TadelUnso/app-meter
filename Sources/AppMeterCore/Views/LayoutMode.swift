import Foundation

/// How the panel arranges itself for a given number of apps.
///
/// Deliberately a pure function of the count and nothing else: the layout must
/// not depend on whether the figures have arrived yet, or the panel would
/// reshuffle itself on every refresh.
public enum LayoutMode: Equatable {
    /// Nothing configured. The panel explains itself instead of showing zeroes.
    case empty
    /// One app, one card per store, figures as large as they go.
    case single
    /// Two to four apps, one card each in a 2-column grid.
    case grid
    /// Five or more: a row per app, two figure columns.
    case rows

    /// Cards per row in `.grid`. One number so the view and its tests cannot
    /// disagree about it.
    public static let gridColumns = 2

    public static func mode(for count: Int) -> LayoutMode {
        switch count {
        case ..<1: .empty
        case 1: .single
        case 2...4: .grid
        default: .rows
        }
    }

    /// What the title bar says. One app names itself; a panel showing several
    /// names the panel, because no one of them speaks for the rest.
    public static func title(for rows: [AppRow]) -> String {
        rows.count == 1 ? rows[0].name : "App Meter"
    }

    /// How much room the title has before it reaches the centred Ko-fi capsule.
    ///
    /// The two sit in separate layers of a `ZStack`, so neither can negotiate
    /// width with the other: left alone, a long app name draws straight over
    /// the capsule, and the title's own truncation does not save it — that is
    /// governed by the lock at the far end of the row, some 190 pt further on.
    /// Capping the title here is what turns the collision into an ellipsis.
    ///
    /// A `kofi` of zero means the capsule has not reported its width yet, on
    /// the very first layout pass. Unconstrained is the right answer there: a
    /// limit of zero would collapse the title and let it spring open a frame
    /// later, which reads as a flicker.
    ///
    /// Lives here rather than in the view so it can be tested without one.
    public static func titleLimit(content: Double, kofi: Double, gap: Double) -> Double {
        guard kofi > 0 else { return .infinity }
        return max(0, (content - kofi) / 2 - gap)
    }

    /// The two stores of one app, added up — or nil when there is nothing
    /// meaningful to add. Lives here rather than in the view because the footer
    /// that shows it is built beside the freshness line, a level above the
    /// layout that knows about rows.
    public static func combinedTotal(for rows: [AppRow]) -> String? {
        guard rows.count == 1, let row = rows.first,
              row.appStore != nil, row.googlePlay != nil
        else { return nil }
        return "\(Fmt.installs(row.lifetime)) together · \(Fmt.delta(row.today)) today"
    }
}

extension Array {
    /// Splits into fixed-size groups, the last one short if the count does not
    /// divide evenly. Used to build the grid's rows.
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
