import SwiftUI

/// Mini version of the app icon: three ascending bars, in the same three
/// colours the .icns uses — track, App Store lavender, growth green.
struct TitleGlyphView: View {
    let scale: Double

    /// Bar heights relative to the tallest, matching Scripts/make-icon.swift.
    private static let bars: [(fraction: CGFloat, colour: Color)] = [
        (0.50, Theme.track),
        (0.75, Theme.appStore),
        (1.00, Theme.accent),
    ]

    private var barWidth: CGFloat { 2.5 * scale }
    private var maxHeight: CGFloat { 11 * scale }

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5 * scale) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(bar.colour)
                    .frame(width: barWidth, height: maxHeight * bar.fraction)
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
    }
}
