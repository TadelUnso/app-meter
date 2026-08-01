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
