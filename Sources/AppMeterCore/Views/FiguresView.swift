import SwiftUI

/// The figures themselves, laid out by `LayoutMode`: one app fills the panel,
/// a few share a grid, many collapse into rows.
struct FiguresView: View {
    let rows: [AppRow]
    let problems: [String]
    let isLoading: Bool
    let scale: Double

    private var mode: LayoutMode { LayoutMode.mode(for: rows.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            switch mode {
            case .empty:
                placeholder
            // Tasks 5-7 rewrite these to render `rows`; for now they stay
            // empty so the panel builds without lying about single-app or
            // grid figures it cannot yet produce.
            case .single, .grid, .rows:
                EmptyView()
            }

            // Problems ride under the figures, never in place of them: stale
            // numbers plus a note beat a panel that goes blank on one bad poll.
            ForEach(problems, id: \.self) { problem in
                Text(problem)
                    .font(Theme.caption(scale: scale))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            }
        }
    }

    private var placeholder: some View {
        Text(isLoading ? "Fetching install counts…" : "No apps yet — add your keys in Settings")
            .font(Theme.caption(scale: scale))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22 * scale)
    }
}

/// One app on one store, as a card: name and store dot up top, the lifetime
/// figure as the centrepiece, the day's movement under it.
private struct FigureCard: View {
    let figures: AppFigures
    let scale: Double
    /// The single-app layout lets the figure take the full display size; cards
    /// sharing a grid take a smaller one.
    let prominent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 5 * scale) {
                StoreDot(store: figures.store, scale: scale)
                Text(figures.name)
                    .font(Theme.label(scale: scale))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(Fmt.installs(figures.lifetime))
                .font(prominent ? Theme.value(scale: scale) : Theme.value(scale: scale * 0.62))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            DeltaText(value: figures.today, scale: scale)
        }
        .padding(12 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                .fill(Theme.panel.opacity(0.55))
        )
    }
}

/// One app on one store, as a line: for the five-and-up layout, where cards
/// would push the panel taller than the screen.
private struct FigureRow: View {
    let figures: AppFigures
    let scale: Double

    var body: some View {
        HStack(spacing: 8 * scale) {
            StoreDot(store: figures.store, scale: scale)

            Text(figures.name)
                .font(Theme.caption(scale: scale))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8 * scale)

            Text(Fmt.installs(figures.lifetime))
                .font(Theme.caption(scale: scale))
                .foregroundStyle(Theme.text)

            DeltaText(value: figures.today, scale: scale)
                .frame(minWidth: 44 * scale, alignment: .trailing)
        }
        .padding(.vertical, 5 * scale)
        .padding(.horizontal, 10 * scale)
        .background(
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .fill(Theme.panel.opacity(0.55))
        )
    }
}

/// The day's movement. Green when something arrived, dim dash when nothing —
/// the dash is `Fmt.delta`'s doing, the colour follows it.
private struct DeltaText: View {
    let value: Int
    let scale: Double

    var body: some View {
        Text(Fmt.delta(value))
            .font(Theme.delta(scale: scale))
            .foregroundStyle(value > 0 ? Theme.accent : Theme.dim)
    }
}

/// The store marker: a small filled circle in the store's pastel, no logo.
/// Brand marks at nine points would be smudges; a colour code reads instantly
/// once seen beside the two-store pair a single app produces.
private struct StoreDot: View {
    let store: Store
    let scale: Double

    var body: some View {
        Circle()
            .fill(store == .appStore ? Theme.appStore : Theme.googlePlay)
            .frame(width: 6 * scale, height: 6 * scale)
            .help(store == .appStore ? "App Store" : "Google Play")
    }
}
