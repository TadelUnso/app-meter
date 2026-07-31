import Foundation

/// One day of Apple's SALES / SUMMARY report, parsed.
///
/// The file is tab-separated with a header row, and Apple has added columns to
/// it over the years — so columns are looked up by name and everything else is
/// ignored. Positional parsing would break on the next column Apple appends.
public struct SalesReport: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let appleIdentifier: String
        public let title: String
        public let sku: String
        /// What the row counts: a first download, an update, a redownload, an
        /// in-app purchase. Apple's own vocabulary, kept as printed.
        public let productTypeIdentifier: String
        public let units: Int
    }

    public let rows: [Row]

    public enum Failure: LocalizedError {
        case missingColumns([String])
        case unreadableUnits(String)

        public var errorDescription: String? {
            switch self {
            case let .missingColumns(names):
                "The sales report has no \(names.joined(separator: ", ")) column."
            case let .unreadableUnits(value):
                "The sales report has \"\(value)\" where a number of units belongs."
            }
        }
    }

    private enum Column {
        static let appleIdentifier = "Apple Identifier"
        static let title = "Title"
        static let sku = "SKU"
        static let productType = "Product Type Identifier"
        static let units = "Units"

        static let required = [appleIdentifier, title, sku, productType, units]
    }

    public init(tsv: String) throws {
        let lines = tsv.split(whereSeparator: \.isNewline)
        guard let header = lines.first else {
            self.rows = []
            return
        }

        let columns = header.components(separatedBy: "\t")
        var index: [String: Int] = [:]
        for (position, name) in columns.enumerated() {
            index[name.trimmingCharacters(in: .whitespaces)] = position
        }

        let missing = Column.required.filter { index[$0] == nil }
        guard missing.isEmpty else { throw Failure.missingColumns(missing) }

        self.rows = try lines.dropFirst().compactMap { line in
            let fields = line.components(separatedBy: "\t")
            // Apple ends the file with a blank line, and a totals line has
            // appeared in some report versions. Anything too short to be a data
            // row is not one.
            guard fields.count >= columns.count else { return nil }

            func field(_ name: String) -> String {
                fields[index[name]!].trimmingCharacters(in: .whitespaces)
            }

            let rawUnits = field(Column.units)
            guard let units = Int(rawUnits) else { throw Failure.unreadableUnits(rawUnits) }

            return Row(
                appleIdentifier: field(Column.appleIdentifier),
                title: field(Column.title),
                sku: field(Column.sku),
                productTypeIdentifier: field(Column.productType),
                units: units
            )
        }
    }

    /// Product type identifiers that mean "someone got this app for the first
    /// time".
    ///
    /// Updates (the 7 family) and redownloads (the 3 family) are deliberately
    /// out: they are the same person again, and counting them would make the
    /// day's growth larger than the number of new people. In-app purchases
    /// (IA…) are not downloads at all.
    ///
    /// An identifier outside this set is ignored rather than guessed at. Run
    /// with `APP_METER_DUMP_SALES=1` to see the identifiers a real report
    /// actually carries, including any this set does not yet know.
    public static let firstDownloadTypes: Set<String> = [
        "1",    // iPhone
        "1F",   // iPad
        "1T",   // universal
        "1E",   // custom app, iPhone
        "1EP",  // custom app, iPad
        "1EU",  // custom app, universal
        "F1",   // Mac
    ]

    /// First-time downloads per app, keyed by Apple identifier, with the title
    /// carried along — the report is the only place App Meter learns an app's
    /// name from.
    public func firstDownloads() -> [String: (title: String, units: Int)] {
        var totals: [String: (title: String, units: Int)] = [:]

        for row in rows where Self.firstDownloadTypes.contains(row.productTypeIdentifier) {
            let running = totals[row.appleIdentifier]?.units ?? 0
            totals[row.appleIdentifier] = (row.title, running + row.units)
        }

        return totals
    }

    /// Every product type the report mentions, with its unit total. Only used
    /// by the debug dump, where the point is to see what Apple actually sends.
    public func unitsByProductType() -> [String: Int] {
        rows.reduce(into: [:]) { $0[$1.productTypeIdentifier, default: 0] += $1.units }
    }
}
