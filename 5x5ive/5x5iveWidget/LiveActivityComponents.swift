import SwiftUI
import WidgetKit

// MARK: - Meta label

/// All-caps monospaced metadata. Same role as the app's `MetaLabel`, local to
/// the extension so it can vary size per surface.
struct LAMetaLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = LATheme.textDim

    var body: some View {
        Text(text.uppercased())
            .font(LATheme.Font.label(size))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

// MARK: - Workout A/B badge

struct WorkoutBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(LATheme.accentInk)
            .padding(.vertical, 2)
            .padding(.horizontal, 5)
            .background(LATheme.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Exercise header row

/// Badge + name + target weight. Used on the lock screen and, split across
/// leading/trailing regions, in the expanded island.
struct ExerciseHeaderRow: View {
    let state: WorkoutActivityAttributes.ContentState
    var nameSize: CGFloat = 17
    var weightSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 8) {
            WorkoutBadge(label: state.workoutTypeLabel)
            Text(state.currentExerciseName)
                .font(LATheme.Font.title(nameSize))
                .tracking(-0.2)
                .foregroundStyle(LATheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(state.targetWeightLabel)
                .font(LATheme.Font.numeric(weightSize, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(LATheme.textSecondary)
        }
    }
}

// MARK: - Drain bar

/// The rest countdown as a capsule that drains left-to-right.
///
/// Built on `ProgressView(timerInterval:)` so the SYSTEM animates it — a
/// Live Activity cannot re-render on a timer, and pushing a ContentState per
/// second gets the activity throttled.
struct RestDrainBar: View {
    let window: ClosedRange<Date>
    var height: CGFloat = 5

    var body: some View {
        ProgressView(timerInterval: window, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(DrainBarStyle(height: height))
    }
}

struct DrainBarStyle: ProgressViewStyle {
    var height: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(LATheme.borderStrong)
                Capsule()
                    .fill(LATheme.accent)
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 1))
            }
        }
        .frame(height: height)
    }
}

/// Non-animating variant. For StandBy / Always-On, where a live ProgressView
/// buys nothing at a 1Hz refresh, and for previews.
struct StaticDrainTrack: View {
    let fraction: Double
    var height: CGFloat = 5
    var trackColor: Color = LATheme.borderStrong
    var fillColor: Color = LATheme.accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(fillColor)
                    .frame(width: geometry.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Set tiles

/// One tile. Palette lifted verbatim from the app's `SetTile`.
struct LASetTile: View {
    let state: SetTileState
    var height: CGFloat = LATheme.Tile.lockHeight
    var radius: CGFloat = LATheme.Tile.lockRadius
    var fontSize: CGFloat = LATheme.Tile.lockFont

    @State private var breathing = false

    private var fill: Color {
        switch state {
        case .hit: LATheme.accentFill
        case .miss: LATheme.missFill
        case .next: LATheme.surfaceSunken.opacity(0.9)
        case .empty: LATheme.surfaceSunken
        }
    }

    private var stroke: Color {
        switch state {
        case .hit: LATheme.accentStroke
        case .miss: LATheme.missStroke
        case .next: LATheme.borderFocus
        case .empty: LATheme.border
        }
    }

    private var textColor: Color {
        switch state {
        case .hit: LATheme.accentText
        case .miss: LATheme.miss
        case .next: LATheme.textMuted
        case .empty: LATheme.textFaint
        }
    }

    private var isNext: Bool { if case .next = state { true } else { false } }

    var body: some View {
        Text(state.label)
            .font(LATheme.Font.numeric(fontSize))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: isNext ? 1.5 : 1)
            )
            .opacity(isNext && breathing ? 0.55 : 1)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = isNext }
    }
}

struct SetTileStrip: View {
    let tiles: [SetTileState]
    var height: CGFloat = LATheme.Tile.lockHeight
    var radius: CGFloat = LATheme.Tile.lockRadius
    var fontSize: CGFloat = LATheme.Tile.lockFont

    var body: some View {
        HStack(spacing: LATheme.Tile.gap) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                LASetTile(state: tile, height: height, radius: radius, fontSize: fontSize)
            }
        }
    }
}

/// Compact-island stand-in for the tile strip: one dot per set.
struct SetDots: View {
    let tiles: [SetTileState]
    var diameter: CGFloat = 6

    private func color(for tile: SetTileState) -> Color {
        switch tile {
        case .hit: LATheme.accent
        case .miss: LATheme.miss
        case .next: LATheme.borderFocus
        case .empty: LATheme.borderStrong
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                Circle()
                    .fill(color(for: tile))
                    .frame(width: diameter, height: diameter)
            }
        }
    }
}

/// Always-On stand-in: the tile strip as five capsules, no text.
struct SetBars: View {
    let tiles: [SetTileState]

    private func color(for tile: SetTileState) -> Color {
        switch tile {
        case .hit: LATheme.accent.opacity(0.5)
        case .miss: LATheme.miss.opacity(0.45)
        case .next: LATheme.borderStrong
        case .empty: LATheme.hairline
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                Capsule()
                    .fill(color(for: tile))
                    .frame(width: 22, height: 5)
            }
        }
    }
}

// MARK: - Progress ring

/// The drain bar wrapped into a circle, for the island's compact and minimal
/// regions and the StandBy trailing dial.
struct RestRing: View {
    let window: ClosedRange<Date>
    var diameter: CGFloat = 25
    var lineWidth: CGFloat = 3

    var body: some View {
        ProgressView(timerInterval: window, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(RingStyle(diameter: diameter, lineWidth: lineWidth))
    }
}

struct RingStyle: ProgressViewStyle {
    var diameter: CGFloat = 25
    var lineWidth: CGFloat = 3
    var trackColor: Color = LATheme.borderStrong
    var fillColor: Color = LATheme.accent

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, configuration.fractionCompleted ?? 1))
                .stroke(fillColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Static ring with a label inside — StandBy's 3/5 dial.
struct StaticRing: View {
    let fraction: Double
    let label: String
    var diameter: CGFloat = 92
    var lineWidth: CGFloat = 11
    var trackColor: Color = LATheme.hairline
    var fillColor: Color = LATheme.accent.opacity(0.55)
    var labelColor: Color = LATheme.textDim.opacity(0.7)

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(fillColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(LATheme.Font.label(13))
                .tracking(1)
                .foregroundStyle(labelColor)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Skip button

struct SkipRestButton: View {
    var body: some View {
        Button(intent: SkipRestIntent()) {
            LAMetaLabel(text: "Skip", color: LATheme.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(LATheme.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
