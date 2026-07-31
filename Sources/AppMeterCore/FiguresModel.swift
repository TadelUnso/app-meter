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
    /// Everything the panel renders, both stores together, stable order:
    /// grouped by app name so the same app's two store cards sit side by side.
    @Published public private(set) var figures: [AppFigures] = []

    /// The most recent refresh's problems, one line per store, empty when all
    /// is well. Shown small under the cards, never in place of them.
    @Published public private(set) var problems: [String] = []

    /// True until the first refresh finishes, one way or the other — what
    /// separates "no apps configured" from "still asking".
    @Published public private(set) var isLoading = true

    private var byStore: [Store: [AppFigures]] = [:]
    private var timer: Timer?

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
            figures = Self.merged([
                .appStore: [
                    AppFigures(id: "1", name: "Lantern", store: .appStore, lifetime: 48_213, today: 316, asOf: day),
                    AppFigures(id: "2", name: "Tidepool", store: .appStore, lifetime: 7_492, today: 0, asOf: day),
                ],
                .googlePlay: [
                    AppFigures(id: "3", name: "Lantern", store: .googlePlay, lifetime: 61_840, today: 428, asOf: day),
                    AppFigures(id: "4", name: "Tidepool", store: .googlePlay, lifetime: 12_066, today: 57, asOf: day),
                ],
            ])
            isLoading = false
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
        NSLog("[model] refresh started")
        defer { NSLog("[model] refresh finished: %d figure(s), %d problem(s)", figures.count, problems.count) }
        var newProblems: [String] = []

        if let account = StoreAccounts.appStoreConnect() {
            do {
                byStore[.appStore] = try await AppleInstallsService(
                    client: AppStoreConnectClient(account: account)
                ).figures()
            } catch {
                newProblems.append("App Store: \(error.localizedDescription)")
            }
        } else {
            byStore[.appStore] = nil
        }

        if let client = StoreAccounts.googlePlay() {
            do {
                byStore[.googlePlay] = try await PlayInstallsService(client: client).figures()
            } catch {
                newProblems.append("Google Play: \(error.localizedDescription)")
            }
        } else {
            byStore[.googlePlay] = nil
        }

        figures = Self.merged(byStore)
        problems = newProblems
        isLoading = false
    }

    /// Both stores' figures in one list: sorted by name so an app published on
    /// both sits together, the store dot telling the two cards apart.
    /// Pure, hence nonisolated — and testable without an actor hop.
    nonisolated static func merged(_ byStore: [Store: [AppFigures]]) -> [AppFigures] {
        byStore.values.flatMap { $0 }.sorted {
            ($0.name.localizedLowercase, $0.store.rawValue) < ($1.name.localizedLowercase, $1.store.rawValue)
        }
    }
}
