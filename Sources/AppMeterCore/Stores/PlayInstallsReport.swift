import Foundation

/// One month of Play Console's installs overview, parsed.
///
/// Two things about these files catch people out, and both are handled here:
/// they are UTF-16 with a byte-order mark, and they carry a running total
/// alongside the daily figures — so unlike Apple's reports, the lifetime count
/// is simply read rather than reconstructed.
public struct PlayInstallsReport: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public let date: Date
        public let packageName: String
        /// Google's own cumulative column. Users, not devices: one person with
        /// a phone and a tablet is one install, which is the figure a developer
        /// means by "how many people have this".
        public let totalUserInstalls: Int
        public let dailyUserInstalls: Int
    }

    public let days: [Day]

    /// The newest day in the file. Play publishes several days behind, so this
    /// is what the panel means by "today".
    public var latest: Day? { days.last }

    public enum Failure: LocalizedError, Equatable {
        case unreadableEncoding
        case missingColumns([String])

        public var errorDescription: String? {
            switch self {
            case .unreadableEncoding:
                "The Play installs report is not text in any encoding Play uses."
            case let .missingColumns(names):
                "The Play installs report has no \(names.joined(separator: ", ")) column."
            }
        }
    }

    private enum Column {
        static let date = "Date"
        static let package = "Package Name"
        static let total = "Total User Installs"
        static let daily = "Daily User Installs"

        static let required = [date, package, total, daily]
    }

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public init(csv data: Data) throws {
        guard let text = Self.decode(data) else { throw Failure.unreadableEncoding }
        try self.init(text: text)
    }

    init(text: String) throws {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let header = lines.first else {
            self.days = []
            return
        }

        var index: [String: Int] = [:]
        for (position, name) in Self.fields(of: String(header)).enumerated() {
            index[name] = position
        }

        let missing = Column.required.filter { index[$0] == nil }
        guard missing.isEmpty else { throw Failure.missingColumns(missing) }

        self.days = lines.dropFirst().compactMap { line in
            let fields = Self.fields(of: String(line))
            guard fields.count >= index.count else { return nil }

            func field(_ name: String) -> String { fields[index[name]!] }

            // A row whose date does not parse is not a day — Play appends no
            // totals row today, but a file that gains one must not become an
            // install count of zero.
            guard let date = Self.dayFormat.date(from: field(Column.date)) else { return nil }

            return Day(
                date: date,
                packageName: field(Column.package),
                totalUserInstalls: Int(field(Column.total)) ?? 0,
                dailyUserInstalls: Int(field(Column.daily)) ?? 0
            )
        }
    }

    /// Play writes UTF-16 with a BOM; the BOM is what says which byte order.
    /// UTF-8 is accepted too, so a file saved out by hand still reads.
    private static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        return String(data: data, encoding: .utf8)
    }

    /// Splits one CSV line. Play quotes its header names and package names, and
    /// a quoted field may contain a comma — an app title in another column has
    /// every chance of doing so.
    private static func fields(of line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if quoted {
                if character == "\"" {
                    // A doubled quote inside a quoted field is one quote.
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }

            index += 1
        }

        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }
}
