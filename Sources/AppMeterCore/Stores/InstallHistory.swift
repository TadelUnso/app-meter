import Foundation

/// What App Meter remembers between launches: the first-download counts of
/// periods that can no longer change.
///
/// This is what makes the lifetime total affordable. A closed year, month or
/// day is fetched once ever; only the open ones are re-read on each refresh.
/// A period that turned out to have no report is remembered as zero, so a quiet
/// month is not re-requested forever.
public struct InstallHistory: Codable, Equatable, Sendable {
    /// Bumped by a future release that needs to invalidate this file rather
    /// than silently inherit a shape it can no longer make sense of. Every
    /// file on disk today predates this field, so it must decode as if it
    /// said 1 rather than fail to load.
    public private(set) var version: Int
    /// Period cache key → Apple identifier → first downloads.
    public private(set) var periods: [String: [String: Int]]
    /// Apple identifier → the title last seen for it. Kept apart from the
    /// counts because a rename must not invalidate a closed period.
    public private(set) var titles: [String: String]

    public init(periods: [String: [String: Int]] = [:], titles: [String: String] = [:], version: Int = 1) {
        self.version = version
        self.periods = periods
        self.titles = titles
    }

    private enum CodingKeys: String, CodingKey {
        case version, periods, titles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Synthesized Decodable would reject a file written before this field
        // existed instead of defaulting it, so the container is read by hand.
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        periods = try container.decode([String: [String: Int]].self, forKey: .periods)
        titles = try container.decode([String: String].self, forKey: .titles)
    }

    public func units(for period: SalesPeriod) -> [String: Int]? {
        periods[period.cacheKey]
    }

    public mutating func store(_ units: [String: Int], titles newTitles: [String: String], for period: SalesPeriod) {
        periods[period.cacheKey] = units
        remember(titles: newTitles)
    }

    public mutating func remember(titles newTitles: [String: String]) {
        titles.merge(newTitles) { _, latest in latest }
    }
}

/// The history on disk.
///
/// Application Support rather than defaults: this grows with every day the
/// widget runs, and a preferences plist is the wrong place for a dataset.
public actor InstallHistoryStore {
    private let url: URL
    private var history: InstallHistory

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
        self.history = (try? Data(contentsOf: self.url))
            .flatMap { try? JSONDecoder().decode(InstallHistory.self, from: $0) }
            ?? InstallHistory()
    }

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("App Meter/apple-installs.json")
    }

    public var current: InstallHistory { history }

    public func units(for period: SalesPeriod) -> [String: Int]? {
        history.units(for: period)
    }

    /// Writes through on every store. The file is a few kilobytes and a refresh
    /// touches it a handful of times, so batching would buy nothing but a
    /// window in which a crash loses the fetches.
    ///
    /// Only ever called for a period that is already closed. Caching one that
    /// is still open would freeze it half-written: today's report, cached at
    /// noon, would be read back tomorrow — when the day counts as closed — as
    /// if it were the whole day.
    public func store(_ units: [String: Int], titles: [String: String], for period: SalesPeriod) {
        history.store(units, titles: titles, for: period)
        save()
    }

    /// Names without counts, for the open periods whose figures must not be
    /// cached but whose titles are the freshest there are.
    public func remember(titles: [String: String]) {
        guard !titles.isEmpty else { return }
        history.remember(titles: titles)
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(history).write(to: url, options: .atomic)
        } catch {
            // A cache that cannot be written costs requests, not correctness:
            // the next refresh re-fetches what it could not remember.
            NSLog("[history] could not save: %@", error.localizedDescription)
        }
    }
}
