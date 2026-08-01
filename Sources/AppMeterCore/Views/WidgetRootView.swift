import AppKit
import SwiftUI

/// The desktop panel.
///
/// Width is the user's; height is whatever the content needs. SwiftUI measures
/// itself and reports the height back through `onHeightChange` — the app shell
/// does not measure the hosting view. Measuring from the shell means resizing
/// the window, which writes the frame to defaults, which notifies the shell,
/// which measures again: a loop that never settles.
public struct WidgetRootView: View {
    private let onHeightChange: (CGFloat) -> Void

    @AppStorage(WidgetSettings.widgetWidthKey) private var widgetWidth = WidgetSettings.defaultWidth
    @AppStorage(WidgetSettings.positionLockedKey) private var positionLocked = false
    @AppStorage(WidgetSettings.widgetVisibleKey) private var widgetVisible = true
    @AppStorage(WidgetSettings.refreshIntervalKey) private var refreshInterval = WidgetSettings.defaultRefreshInterval

    @StateObject private var model = FiguresModel()
    @State private var dragStartWidth: Double?

    public init(onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.onHeightChange = onHeightChange
    }

    /// Everything scales from the 520 pt design width, so the composition is
    /// identical at every panel size.
    private var width: CGFloat { WidgetSettings.clampWidth(widgetWidth) }
    private var scale: Double { width / WidgetSettings.defaultWidth }
    private var pad: CGFloat { 14 * scale }
    private var gap: CGFloat { 12 * scale }

    public var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            titleBar
            FiguresView(
                rows: model.rows,
                problems: model.problems,
                isLoading: model.isLoading,
                scale: scale
            )
        }
        .onAppear { model.start() }
        // Rebuilding the timer on any change of the stored interval; the other
        // defaults this view reads redraw it anyway.
        .onChange(of: refreshInterval) { _, _ in model.start() }
        .padding(pad)
        .frame(width: width)
        .background(
            ZStack {
                PanelBackground()
                Theme.panel.opacity(0.35)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
        )
        .overlay { resizeGrips }
        // Measures the panel's *ideal* height, and must stay above the
        // stretching frame below. Applied after it, the reader would report the
        // window's current height instead: the panel would agree with whatever
        // size the window already had, the window would never be corrected, and
        // a height latched while the width was still moving would leave the
        // content clipped to a sliver.
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                    onHeightChange(height)
                }
            }
        }
        // Absorbs whatever height the hosting view imposes, so the panel above
        // keeps its own size while the window catches up.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Always-visible first row: name on the left, controls on the right, Ko-fi
    /// centred behind them — the same arrangement as the sibling mole-widget.
    ///
    /// Permanently visible rather than fading in on hover: the lock lives here,
    /// and a control that hides itself is a control you have to remember exists.
    private var titleBar: some View {
        ZStack {
            KofiButton(scale: scale)

            HStack(spacing: 6 * scale) {
                TitleGlyphView(scale: scale)

                Text(LayoutMode.title(for: model.rows))
                    .font(Theme.title(scale: scale))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                HStack(spacing: 2 * scale) {
                    Button {
                        positionLocked.toggle()
                    } label: {
                        controlIcon(positionLocked ? "lock.fill" : "lock.open",
                                    tint: positionLocked ? Theme.warning : Theme.dim)
                    }
                    .buttonStyle(.plain)
                    .help(positionLocked
                        ? "Position and size are locked — click to unlock"
                        : "Click to lock the widget position and size")

                    Button {
                        widgetVisible = false
                    } label: {
                        controlIcon("eye.slash", tint: Theme.dim)
                    }
                    .buttonStyle(.plain)
                    .help("Hide widget — bring it back from the menu bar icon")
                }
            }
        }
    }

    /// Same proportions as mole-widget's lock and hide buttons: an 11 pt glyph
    /// in a 20 pt hit area, so the target is comfortably larger than the icon.
    private func controlIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 11 * scale, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 20 * scale, height: 20 * scale)
            .contentShape(Rectangle())
    }

    /// Which side of the frame a grip sits on, and how a drag there maps to a
    /// change in width.
    ///
    /// Only the vertical edges have grips: height follows the content, so a
    /// top or bottom grip would have nothing to change.
    private enum Grip: CaseIterable {
        case leading, trailing

        var alignment: Alignment {
            switch self {
            case .leading: .leading
            case .trailing: .trailing
            }
        }

        /// Outward is positive: dragging an edge away from the centre grows the
        /// panel, whichever edge it is.
        func delta(_ translation: CGSize) -> Double {
            switch self {
            case .leading: -translation.width
            case .trailing: translation.width
            }
        }
    }

    private var resizeGrips: some View {
        ZStack {
            ForEach(Array(Grip.allCases), id: \.self) { grip in
                gripView(grip)
            }
        }
    }

    /// An invisible strip along one edge. Ten points at the design size — wide
    /// enough to grab without hunting, narrow enough to leave the rest of the
    /// panel free for dragging the window.
    ///
    /// The modifier order is load-bearing: `contentShape` has to come while the
    /// view is still strip-sized. Applied after the expanding frame it would
    /// claim the entire panel as its hit area, and every drag anywhere — even
    /// in the middle — would resize instead of moving the window.
    private func gripView(_ grip: Grip) -> some View {
        let thickness = 10 * scale

        return Color.clear
            .frame(width: thickness)
            .contentShape(Rectangle())
            .onHover { inside in
                guard !positionLocked else { return }
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        guard !positionLocked else { return }
                        let start = dragStartWidth ?? widgetWidth
                        dragStartWidth = start
                        widgetWidth = WidgetSettings.clampWidth(start + grip.delta(value.translation))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: grip.alignment)
    }
}

/// "Ko-fi | Support" capsule opening the donation page, mirroring the sibling
/// mole-widget and claude-usage-widget.
private struct KofiButton: View {
    let scale: Double

    @State private var hovering = false

    private let kofiRed = Color(red: 1.0, green: 0.369, blue: 0.357) // #FF5E5B
    private let kofiBg = Color(red: 0.10, green: 0.10, blue: 0.10) // near-black

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/tadel_unso")!)
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 4 * scale) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 9 * scale, weight: .medium))
                    Text("Ko-fi")
                        .font(.system(size: 10 * scale, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7 * scale)
                .padding(.vertical, 3 * scale)
                .background(kofiBg)

                Text("Support")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7 * scale)
                    .padding(.vertical, 3 * scale)
                    .background(kofiRed)
            }
            .clipShape(Capsule())
            .opacity(hovering ? 0.80 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Support this widget on Ko-fi")
    }
}

/// The frosted backdrop. `behindWindow` blending is what makes the panel read
/// as glass over the wallpaper rather than a flat dark rectangle.
private struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
