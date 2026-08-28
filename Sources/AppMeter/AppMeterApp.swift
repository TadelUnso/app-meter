import AppKit
import AppMeterCore
import ServiceManagement
import Sparkle
import SwiftUI

@main
struct AppMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The only SwiftUI scene left. The menu bar item is an AppKit
    /// `NSStatusItem` built by the delegate instead of a `MenuBarExtra`,
    /// because `MenuBarExtra` gives its status item `.terminationOnRemoval`:
    /// when macOS declines to show the icon — a full menu bar, or the item
    /// landing on Control Center's blocked list — AppKit reads that as "the
    /// user threw the icon away" and quits the app. This widget lives on the
    /// desktop, so losing the icon must cost the menu, not the widget.
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

private var isDraggingAllowed: Bool {
    !UserDefaults.standard.bool(forKey: WidgetSettings.positionLockedKey)
}

/// mouseDownCanMoveWindow == false disables AppKit's built-in auto-drag, which
/// would ignore the lock; dragging goes only through DesktopWindow.mouseDown.
final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless desktop-level window: never steals focus, draggable unless locked.
final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.type == .leftMouseDown, isDraggingAllowed {
            performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: DesktopWindow?
    private var statusItem: NSStatusItem?

    /// Sparkle updater. `startingUpdater: true` kicks off the background check
    /// on launch; the menu's "Check for Updates…" item drives it manually.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon

        installStatusItem()

        let window = DesktopWindow(
            contentRect: NSRect(x: 0, y: 0, width: WidgetSettings.defaultWidth, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // One level above the Finder desktop icon window: below it, Finder's
        // transparent full-screen window swallows every click and the widget
        // cannot be dragged.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false

        window.contentView = WidgetHostingView(
            rootView: WidgetRootView(
                onHeightChange: { [weak self] height in
                    MainActor.assumeIsolated { self?.setHeight(height) }
                },
                onMenu: { [weak self] in
                    MainActor.assumeIsolated { self?.showMenuAtCursor() }
                }
            )
        )

        // Centre first, then attach the autosave name so a stored frame wins.
        window.center()
        window.setFrameAutosaveName("AppMeterWindow")

        self.window = window
        syncWindowSize()
        window.orderFrontRegardless()

        if SalesDump.isEnabled {
            Task { await SalesDump.run() }
        }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncWindowSize()
            }
        }
    }

    /// A system symbol instead of a hand-drawn path: SF Symbols are hinted by
    /// Apple for the exact sizes they get drawn at, including menu bar scale,
    /// which a hand-drawn arc-plus-needle at 16pt could not reliably match —
    /// the two strokes had too little room to stay visually separate. Template
    /// rendering still lets macOS tint it for light/dark menu bars.
    ///
    /// `gauge.with.needle` is available from macOS 14.0 (per the SF Symbols
    /// catalog's own availability metadata), which is this package's declared
    /// floor, so no fallback symbol or nil-handling is needed.
    private static let menuBarIcon: NSImage = {
        let icon = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "App Meter")!
        icon.isTemplate = true
        return icon
    }()

    /// The menu bar icon, built by hand rather than through `MenuBarExtra`.
    ///
    /// `behavior` is left at its default empty set on purpose: the two options
    /// AppKit offers are `.removalAllowed` and `.terminationOnRemoval`, and
    /// `MenuBarExtra` sets both. That is what made a hidden icon fatal — macOS
    /// asking the item to stop being visible is delivered as a removal, and the
    /// app then quits before the desktop panel has drawn. With no behavior
    /// flags the item is never treated as removable, so a menu bar that has no
    /// room for it costs the menu and nothing else.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarIcon

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        statusItem = item
    }

    /// The same menu, opened from the widget's own gear button.
    ///
    /// The gear exists because the menu bar icon is not guaranteed to be there:
    /// when macOS blocks it, this is the only way left to reach Settings,
    /// updates, or Quit. Popping up at the cursor rather than under the button
    /// keeps the panel from needing to report its own screen coordinates back
    /// to the shell for the one case where a menu is opened.
    ///
    /// A fresh `NSMenu` per invocation, not the status item's: AppKit tracks a
    /// menu that is currently open, and lending out the one already owned by
    /// the status item invites the two presentations to fight over it.
    private func showMenuAtCursor() {
        let menu = NSMenu()
        menu.delegate = self
        // An accessory app is never the active application, and an unactivated
        // menu swallows the first click that would otherwise pick an item.
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// The height SwiftUI last measured for its own content. Nil until the
    /// first layout, when the window keeps whatever height it launched with.
    private var contentHeight: CGFloat?
    private var isResizing = false

    private func syncWindowSize() {
        applyGeometry()
    }

    private func setHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        contentHeight = height
        applyGeometry()
    }

    /// The single place the window's frame is set, composed from the two
    /// independent inputs: the width the user stored, and the height SwiftUI
    /// measured.
    ///
    /// Keeping it in one function is what makes it safe to call from both the
    /// defaults observer and the height reporter. The trailing guard makes a
    /// repeat call a no-op, so nothing here can oscillate.
    ///
    /// AppKit anchors a resize to the window's bottom-left, which would make the
    /// panel appear to crawl up the screen as it grows. Re-pinning the top-left
    /// keeps it where the user put it, whichever edge they dragged.
    private func applyGeometry() {
        guard let window else { return }

        // Resizing lays the hosting view out again, which reports a new height
        // through setHeight while this call is still on the stack. Re-entering
        // must be deferred rather than dropped: dropping loses the correction
        // for good, and the height then stays wrong until something unrelated
        // moves it.
        guard !isResizing else {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.applyGeometry() }
            }
            return
        }

        let width = WidgetSettings.width(in: .standard)
        let height = contentHeight ?? window.frame.height
        guard height > 0 else { return }
        guard abs(window.frame.width - width) > 0.5 || abs(window.frame.height - height) > 0.5 else { return }

        isResizing = true
        defer { isResizing = false }

        let top = window.frame.maxY
        window.setContentSize(NSSize(width: width, height: height))
        var moved = window.frame
        moved.origin.y = top - moved.height
        window.setFrameOrigin(moved.origin)

        if AppDelegate.logsGeometry {
            NSLog("[geom] want %.1fx%.1f -> frame %@", width, height, NSStringFromRect(window.frame))
        }
    }

    /// Set APP_METER_LOG_GEOMETRY=1 to trace every window resize. Off by
    /// default: this fires on every frame of a resize drag.
    static let logsGeometry = ProcessInfo.processInfo.environment["APP_METER_LOG_GEOMETRY"] == "1"
}

/// The menu, rebuilt on every open.
///
/// Rebuilding rather than toggling stored items is what keeps the two entry
/// points — the menu bar icon and the widget's gear — showing the same state
/// without either of them owning it: the lock, the login registration and
/// Sparkle's readiness are all read fresh from the thing that actually holds
/// them.
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Every item here has a target, which is all AppKit's automatic
        // enabling looks at — it would happily enable "Check for Updates…"
        // while Sparkle is busy. Owning the enabled state is the only way to
        // reflect `canCheckForUpdates`.
        menu.autoenablesItems = false

        menu.addItem(makeItem("App Meter v\(CoreInfo.version) — GitHub", #selector(openRepositoryPage)))
        menu.addItem(makeItem("Report an Issue", #selector(openIssuesPage)))

        let updates = makeItem("Check for Updates…", #selector(checkForUpdates))
        updates.isEnabled = updaterController.updater.canCheckForUpdates
        menu.addItem(updates)

        menu.addItem(.separator())

        let lock = makeItem("Lock position", #selector(togglePositionLock))
        lock.state = UserDefaults.standard.bool(forKey: WidgetSettings.positionLockedKey) ? .on : .off
        menu.addItem(lock)

        let login = makeItem("Launch at login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Quit App Meter", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openRepositoryPage() {
        NSWorkspace.shared.open(UpdateChecker.repoPageURL)
    }

    @objc private func openIssuesPage() {
        NSWorkspace.shared.open(UpdateChecker.issuesPageURL)
    }

    @objc private func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    @objc private func togglePositionLock() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: WidgetSettings.positionLockedKey),
                     forKey: WidgetSettings.positionLockedKey)
    }

    /// Registration only works from a real .app bundle; from a bare
    /// `swift run` binary register() throws, and the menu simply shows the
    /// unchanged status the next time it opens.
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("[login] toggle failed: %@", error.localizedDescription)
        }
    }

    /// An accessory app has no active application to open a window in front of,
    /// so the settings window would open behind whatever the user was looking
    /// at unless the app is brought forward first.
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
