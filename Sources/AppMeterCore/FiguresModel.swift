import Foundation
import SwiftUI

/// The panel's one source of figures: polls both stores on the configured
/// interval and keeps the last good answer.
///
/// The two stores fail independently — one set of credentials can be wrong, or
/// one API down, while the other half works. So each store's figures are
/// replaced only by that store's own next answer, and an error on one side
/// never blanks the other side's numbers.
@MainActor
public final class FiguresModel: ObservableObject {
    /// Everything the panel renders: one row per app, both stores grouped
    /// inside it, sorted by name.
    @Published public private(set) var rows: [AppRow] = []

    /// The most recent refresh's problems, one line per store, empty when all
    /// is well. Shown small under the cards, never in place of them.
    @Published public private(set) var problems: [String] = []

    /// True until the first refresh finishes, one way or the other — what
    /// separates "no apps configured" from "still asking".
    @Published public private(set) var isLoading = true

    /// When the stores were last successfully asked. Set only when at least
    /// one store answered — a refresh where both fail did not make the
    /// figures any fresher, and moving this forward anyway would tell the
    /// user the numbers are current when they are exactly as stale as before.
    @Published public private(set) var lastRefresh: Date?

    private var byStore: [Store: [AppFigures]] = [:]
    private var timer: Timer?
    /// Guards against two walks running at once. `refresh()` suspends at every
    /// `await`, and a young account's first walk is a thousand-odd sequential
    /// requests, so the poll timer firing mid-walk — or `start()` being called
    /// again because the interval changed in Settings — would otherwise launch
    /// a second full pass against the same key while the first is still going.
    private var refreshing = false

    public init() {}

    /// Fixed, made-up figures instead of the network. For screenshots — the
    /// README must not publish the developer's real install counts.
    static var isDemo: Bool {
        ProcessInfo.processInfo.environment["APP_METER_DEMO"] == "1"
    }

    /// Begins polling. Safe to call again — the timer is rebuilt, which is how
    /// a changed interval takes effect.
    public func start(defaults: UserDefaults = .standard) {
        timer?.invalidate()

        if Self.isDemo {
            let day = Date(timeIntervalSinceNow: -86_400)
            rows = Self.rows([
                .appStore: [
                    AppFigures(id: "com.demo.lantern", name: "Lantern", store: .appStore, lifetime: 48_213, today: 316, asOf: day),
                    AppFigures(id: "com.demo.tidepool", name: "Tidepool", store: .appStore, lifetime: 7_492, today: 0, asOf: day),
                ],
                .googlePlay: [
                    AppFigures(id: "com.demo.lantern", name: "Lantern", store: .googlePlay, lifetime: 61_840, today: 428, asOf: day),
                    AppFigures(id: "com.demo.tidepool", name: "Tidepool", store: .googlePlay, lifetime: 12_066, today: 57, asOf: day),
                ],
            ])
            isLoading = false
            // lastRefresh stays nil: there is no poll behind these fixture
            // figures, so there is nothing true to date them with — the
            // freshness line simply does not appear on screenshots.
            return
        }

        let minutes = defaults.object(forKey: WidgetSettings.refreshIntervalKey) as? Double
            ?? WidgetSettings.defaultRefreshInterval
        let interval = max(minutes, 1) * 60

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }

        Task { await refresh() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() async {
        // A second call while one is already in flight is a no-op, not a
        // queued retry — the timer will ask again on its own schedule, and
        // there is nothing this call would learn that the running one won't.
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        NSLog("[model] refresh started")
        defer { NSLog("[model] refresh finished: %d row(s), %d problem(s)", rows.count, problems.count) }
        var newProblems: [String] = []
        var answered = false

        if let account = StoreAccounts.appStoreConnect() {
            do {
                let installs = try await AppleInstallsService(
                    client: AppStoreConnectClient(account: account)
                ).installs()
                byStore[.appStore] = Self.retainedAppleFigures(existing: byStore[.appStore], incoming: installs)
                // An incomplete answer is not a finished ask: it must not be the
                // thing that tells the footer the figures are fresh.
                if installs.isComplete { answered = true }
                newProblems.append(contentsOf: installs.problems)
            } catch {
                newProblems.append("App Store: \(error.localizedDescription)")
            }
        } else {
            byStore[.appStore] = nil
        }

        if let client = StoreAccounts.googlePlay() {
            do {
                byStore[.googlePlay] = try await PlayInstallsService(client: client).figures()
                answered = true
            } catch {
                newProblems.append("Google Play: \(error.localizedDescription)")
            }
        } else {
            byStore[.googlePlay] = nil
        }

        rows = Self.rows(byStore)
        problems = newProblems
        isLoading = false
        // Only advance the clock when a store actually answered: a refresh
        // where everything failed did not make the figures any fresher, and
        // saying otherwise would be a lie exactly when the user most needs
        // the truth.
        if answered {
            lastRefresh = Date()
        }
    }

    /// Whether an Apple result that stopped partway through the walk may
    /// replace the figures already on screen. This class's own contract is that
    /// a store's figures move only on that store's next *good* answer — a rate
    /// limit cutting the walk short must not let a smaller, partial total
    /// overwrite a complete one. The exception is a first run: there is nothing
    /// to protect yet, so the partial beats an empty panel.
    /// Pure, hence nonisolated — and testable without an actor hop.
    nonisolated static func retainedAppleFigures(existing: [AppFigures]?, incoming: AppleInstalls) -> [AppFigures] {
        guard !incoming.isComplete, let existing else { return incoming.figures }
        return existing
    }

    /// Both stores' figures as one row per app, sorted by name.
    /// Pure, hence nonisolated — and testable without an actor hop.
    nonisolated static func rows(_ byStore: [Store: [AppFigures]]) -> [AppRow] {
        var appStore: [String: AppFigures] = [:]
        var googlePlay: [String: AppFigures] = [:]

        for figures in byStore[.appStore] ?? [] { appStore[figures.id] = figures }
        for figures in byStore[.googlePlay] ?? [] { googlePlay[figures.id] = figures }

        return Set(appStore.keys).union(googlePlay.keys).map { id in
            AppRow(
                id: id,
                // The App Store name is a real title; Play only ever knows the package.
                name: appStore[id]?.name ?? googlePlay[id]?.name ?? id,
                appStore: appStore[id],
                googlePlay: googlePlay[id]
            )
        }
        // Two apps can share a name (same developer, two accounts; a rename
        // in progress). Falling back to the id — unique by construction —
        // keeps their order fixed, instead of the process-seeded hash order
        // Set/union would otherwise leave it in.
        .sorted { ($0.name.localizedLowercase, $0.id) < ($1.name.localizedLowercase, $1.id) }
    }
}
