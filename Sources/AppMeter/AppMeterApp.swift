import AppKit
import AppMeterCore
import ServiceManagement
import Sparkle
import SwiftUI

@main
struct AppMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage(WidgetSettings.positionLockedKey) private var positionLocked = false
    @AppStorage(WidgetSettings.widgetVisibleKey) private var widgetVisible = true

    /// Three ascending bars. Template images get tinted by macOS to match the
    /// menu bar, light or dark.
    private static let menuBarIcon: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            let heights: [CGFloat] = [5, 9, 13]
            for (index, height) in heights.enumerated() {
                let bar = NSRect(x: 2.5 + CGFloat(index) * 4, y: 2, width: 2.5, height: height)
                NSBezierPath(roundedRect: bar, xRadius: 1.2, yRadius: 1.2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            Button("App Meter v\(CoreInfo.version) — GitHub") {
                NSWorkspace.shared.open(UpdateChecker.repoPageURL)
            }
            Button("Report an Issue") {
                NSWorkspace.shared.open(UpdateChecker.issuesPageURL)
            }
            Button("Check for Updates…") {
                appDelegate.updaterController.updater.checkForUpdates()
            }
            .disabled(!appDelegate.updaterController.updater.canCheckForUpdates)
            Divider()
            Toggle("Lock position", isOn: $positionLocked)
            Toggle("Show on desktop", isOn: $widgetVisible)
            LaunchAtLoginToggle()
            Divider()
            // An accessory app has no active application to open a window in
            // front of, so the link alone puts the settings window behind
            // whatever the user was looking at.
            SettingsMenuItem()
            Button("Quit App Meter") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }

        Settings {
            SettingsView()
        }
    }
}

/// Opens the Settings scene.
///
/// An accessory app is never the active application, and the settings window
/// opens behind everything else — or not at all — unless the app is brought
/// forward first. The activation has to happen in the same click, which is why
/// this is a Button around `openSettings` rather than a bare `SettingsLink`.
private struct SettingsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

/// "Launch at login" backed by SMAppService. Registration only works from a
/// real .app bundle; from a bare `swift run` binary register() throws and the
/// toggle reverts.
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    enabled = newValue
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
        ))
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

    /// Sparkle updater. `startingUpdater: true` kicks off the background check
    /// on launch; the menu's "Check for Updates…" item drives it manually.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon

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
            rootView: WidgetRootView(onHeightChange: { [weak self] height in
                MainActor.assumeIsolated { self?.setHeight(height) }
            })
        )

        // Centre first, then attach the autosave name so a stored frame wins.
        window.center()
        window.setFrameAutosaveName("AppMeterWindow")

        self.window = window
        syncWindowSize()
        if WidgetSettings.isVisible(in: .standard) {
            window.orderFrontRegardless()
        }

        if SalesDump.isEnabled {
            Task { await SalesDump.run() }
        }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcileVisibility()
                self?.syncWindowSize()
            }
        }
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

    /// Shows or hides the window to match the stored flag. Idempotent, so
    /// unrelated defaults changes do not re-order the window.
    private func reconcileVisibility() {
        guard let window else { return }
        let shouldBeVisible = WidgetSettings.isVisible(in: .standard)
        if shouldBeVisible, !window.isVisible {
            window.orderFrontRegardless()
        } else if !shouldBeVisible, window.isVisible {
            window.orderOut(nil)
        }
    }
}
