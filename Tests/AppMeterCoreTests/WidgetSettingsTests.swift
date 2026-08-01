import Foundation
import Testing
@testable import AppMeterCore

@Suite("WidgetSettings")
struct WidgetSettingsTests {
    @Test("clamps a width to the allowed range", arguments: [
        (100.0, WidgetSettings.minWidth),
        (WidgetSettings.minWidth, WidgetSettings.minWidth),
        (WidgetSettings.defaultWidth, WidgetSettings.defaultWidth),
        (WidgetSettings.maxWidth, WidgetSettings.maxWidth),
        (5_000.0, WidgetSettings.maxWidth),
    ])
    func clampWidth(width: Double, expected: Double) {
        #expect(WidgetSettings.clampWidth(width) == expected)
    }

    /// The point of the floor: a narrower panel draws its type, spacing and
    /// controls at exactly the size the design gives them, and only loses
    /// horizontal room. Anything below 1 here is the old zoomed-out behaviour.
    @Test("holds the scale at 1 up to the design width", arguments: [
        WidgetSettings.minWidth,
        400.0,
        519.0,
        WidgetSettings.defaultWidth,
    ])
    func scaleIsFlooredAtOne(width: Double) {
        #expect(WidgetSettings.scale(forWidth: width) == 1)
    }

    /// A width under the minimum is clamped before it is scaled, so it cannot
    /// reach through the floor either.
    @Test func scaleIgnoresWidthsBelowTheMinimum() {
        #expect(WidgetSettings.scale(forWidth: 100) == 1)
    }

    @Test("grows linearly above the design width", arguments: [
        (WidgetSettings.defaultWidth * 1.5, 1.5),
        (WidgetSettings.maxWidth, WidgetSettings.maxWidth / WidgetSettings.defaultWidth),
    ])
    func scaleGrowsAboveTheDesignWidth(width: Double, expected: Double) {
        #expect(WidgetSettings.scale(forWidth: width) == expected)
    }

    /// Past the maximum the clamp, not the panel, is what stops growing.
    @Test func scaleStopsAtTheMaximumWidth() {
        #expect(WidgetSettings.scale(forWidth: 5_000)
            == WidgetSettings.scale(forWidth: WidgetSettings.maxWidth))
    }
}
