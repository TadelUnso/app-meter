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
            case .single:
                if let row = rows.first {
                    single(row)
                }
            case .grid:
                grid
            // Task 7 rewrites this to render `rows`; for now it stays empty
            // so the panel builds without lying about row figures it cannot
            // yet produce.
            case .rows:
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

    private func single(_ row: AppRow) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(alignment: .top, spacing: 10 * scale) {
                if let appStore = row.appStore {
                    StoreTile(figures: appStore, scale: scale)
                }
                if let googlePlay = row.googlePlay {
                    StoreTile(figures: googlePlay, scale: scale)
                }
            }

            // Only here: adding up two stores of one app is a real number, adding
            // up two different apps is not.
            if row.appStore != nil, row.googlePlay != nil {
                Text("\(Fmt.installs(row.lifetime)) together · \(Fmt.delta(row.today)) today")
                    .font(Theme.caption(scale: scale))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 10 * scale) {
            ForEach(rows.chunks(of: LayoutMode.gridColumns), id: \.first!.id) { chunk in
                HStack(alignment: .top, spacing: 10 * scale) {
                    ForEach(chunk) { row in
                        AppCard(row: row, scale: scale)
                    }
                    // A short last row keeps its cards the same width as the
                    // full rows above it.
                    if chunk.count < LayoutMode.gridColumns {
                        ForEach(0..<(LayoutMode.gridColumns - chunk.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

/// One app in the grid: its name, then a line per store it is published on.
private struct AppCard: View {
    let row: AppRow
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text(row.name)
                .font(Theme.title(scale: scale * 0.85))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)

            if let appStore = row.appStore {
                StoreLine(figures: appStore, scale: scale)
            }
            if let googlePlay = row.googlePlay {
                StoreLine(figures: googlePlay, scale: scale)
            }
        }
        .padding(12 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                .fill(Theme.panel.opacity(0.55))
        )
    }
}

/// A store's figures on one line: the store named, the total, the day's movement.
/// The date is a tooltip here — naming it on every line would cost more width
/// than the grid has.
private struct StoreLine: View {
    let figures: AppFigures
    let scale: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
            Text(figures.store == .appStore ? "APP STORE" : "GOOGLE PLAY")
                .font(Theme.label(scale: scale))
                .foregroundStyle(figures.store == .appStore ? Theme.appStore : Theme.googlePlay)
                .frame(width: 66 * scale, alignment: .leading)
                .lineLimit(1)

            Text(Fmt.installs(figures.lifetime))
                .font(Theme.value(scale: scale * 0.55))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if figures.today > 0 {
                Text(Fmt.delta(figures.today))
                    .font(Theme.delta(scale: scale))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .help("Figures for \(Fmt.day(figures.asOf))")
    }
}

/// One store's figures inside the single-app layout: the store named above,
/// the lifetime total as the centrepiece, the day's movement and its date under it.
private struct StoreTile: View {
    let figures: AppFigures
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text(figures.store == .appStore ? "APP STORE" : "GOOGLE PLAY")
                .font(Theme.label(scale: scale))
                .foregroundStyle(figures.store == .appStore ? Theme.appStore : Theme.googlePlay)

            Text(Fmt.installs(figures.lifetime))
                .font(Theme.value(scale: scale))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            HStack(spacing: 5 * scale) {
                Text(Fmt.delta(figures.today))
                    .font(Theme.delta(scale: scale))
                    .foregroundStyle(figures.today > 0 ? Theme.accent : Theme.dim)

                // The stores report days apart, so the day is named rather than
                // called "today" — two figures that look equally fresh can be a
                // week apart.
                Text(Fmt.day(figures.asOf))
                    .font(Theme.caption(scale: scale))
                    .foregroundStyle(Theme.dim)
            }
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
