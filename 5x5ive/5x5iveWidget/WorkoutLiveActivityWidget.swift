import WidgetKit
import SwiftUI
import ActivityKit

/// Five surfaces, one visual language: monospaced numerics, the SetTile
/// palette, a draining rest bar. Information priority when space runs out:
/// countdown, sets, weight, next-up.
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenBanner(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(LATheme.textPrimary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        WorkoutBadge(label: state.workoutTypeLabel)
                        Text(state.currentExerciseName)
                            .font(LATheme.Font.title(16))
                            .foregroundStyle(LATheme.textPrimary)
                            .lineLimit(1)
                        Text(state.targetWeightLabel)
                            .font(LATheme.Font.numeric(12, weight: .regular))
                            .foregroundStyle(LATheme.textMuted)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let window = state.restWindow {
                        Text(timerInterval: window, countsDown: true)
                            .font(LATheme.Font.numeric(30))
                            .monospacedDigit()
                            .foregroundStyle(LATheme.accentText)
                    } else {
                        Text("SET \(state.currentSetNumber)")
                            .font(LATheme.Font.numeric(22))
                            .foregroundStyle(LATheme.textPrimary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        if let window = state.restWindow {
                            RestDrainBar(window: window, height: 4)
                        }
                        SetTileStrip(
                            tiles: state.tiles,
                            height: LATheme.Tile.islandHeight,
                            radius: LATheme.Tile.islandRadius,
                            fontSize: LATheme.Tile.islandFont
                        )
                        FooterRow(state: state)
                    }
                }
            } compactLeading: {
                HStack(spacing: 9) {
                    if let window = state.restWindow {
                        RestRing(window: window, diameter: 16, lineWidth: 3)
                    }
                    Text(state.shortExerciseName.uppercased())
                        .font(LATheme.Font.label(11))
                        .tracking(1)
                        .foregroundStyle(LATheme.textMuted)
                }
            } compactTrailing: {
                if let window = state.restWindow {
                    Text(timerInterval: window, countsDown: true)
                        .font(LATheme.Font.numeric(13))
                        .monospacedDigit()
                        .foregroundStyle(LATheme.accentText)
                        // Without this the island clips it to an ellipsis mid-countdown.
                        .frame(width: 42)
                } else {
                    SetDots(tiles: state.tiles)
                }
            } minimal: {
                if let window = state.restWindow {
                    RestRing(window: window, diameter: 25, lineWidth: 3)
                } else {
                    Text(state.setsLabel)
                        .font(LATheme.Font.label(12))
                        .tracking(0.5)
                        .foregroundStyle(LATheme.accentText)
                }
            }
            .keylineTint(LATheme.accent)
        }
    }
}

// MARK: - Lock screen

struct LockScreenBanner: View {
    let state: WorkoutActivityAttributes.ContentState

    /// StandBy and Always-On both arrive here with luminance reduced.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isLuminanceReduced {
            DimmedBanner(state: state)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ExerciseHeaderRow(state: state)

                if let window = state.restWindow {
                    RestingRow(state: state, window: window)
                } else {
                    LiftingRow(state: state)
                }

                SetTileStrip(tiles: state.tiles)
                FooterRow(state: state)
            }
            .padding(20)
        }
    }
}

/// The state the lifter sees most.
private struct RestingRow: View {
    let state: WorkoutActivityAttributes.ContentState
    let window: ClosedRange<Date>

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline) {
                    Text(timerInterval: window, countsDown: true)
                        .font(LATheme.Font.numeric(44))
                        .monospacedDigit()
                        .foregroundStyle(LATheme.accentText)
                        // Keeps the digits from shrinking when the minutes place gains a digit.
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Spacer()
                    LAMetaLabel(text: restLabel)
                }
                RestDrainBar(window: window)
            }
            SkipRestButton()
        }
    }

    private var restLabel: String {
        guard let total = state.restDuration else { return "Rest" }
        let seconds = Int(total.rounded())
        return String(format: "Rest · %d:%02d", seconds / 60, seconds % 60)
    }
}

private struct LiftingRow: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("SET \(state.currentSetNumber)")
                .font(LATheme.Font.numeric(34))
                .tracking(-1)
                .monospacedDigit()
                .foregroundStyle(LATheme.textPrimary)
            LAMetaLabel(text: "of \(state.totalSets) · \(state.targetReps) reps", size: 12)
            Spacer()
        }
    }
}

private struct FooterRow: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack {
            if let next = state.nextExerciseName {
                LAMetaLabel(text: "Next · \(next)")
            }
            Spacer()
            LAMetaLabel(text: "\(state.setsLabel) sets")
        }
    }
}

// MARK: - StandBy / Always-On

/// Dimmed for Always-On (1Hz refresh, burn-in risk); tiles drop their text
/// since glyphs that small are unreadable at that refresh rate.
struct DimmedBanner: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                LAMetaLabel(
                    text: "\(state.currentExerciseName) · \(state.targetWeightLabel)",
                    color: LATheme.textDim.opacity(0.65)
                )

                if let window = state.restWindow {
                    Text(timerInterval: window, countsDown: true)
                        .font(LATheme.Font.numeric(60))
                        .monospacedDigit()
                        .foregroundStyle(LATheme.accent.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("SET \(state.currentSetNumber)")
                        .font(LATheme.Font.numeric(48))
                        .foregroundStyle(LATheme.accent.opacity(0.62))
                }

                SetBars(tiles: state.tiles)
            }
            Spacer()
            StaticRing(fraction: setFraction, label: state.setsLabel)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
    }

    /// Sets, not time — a static ring would lie about a countdown.
    private var setFraction: Double {
        guard state.totalSets > 0 else { return 0 }
        return Double(state.completedSets) / Double(state.totalSets)
    }
}

// MARK: - Previews

extension WorkoutActivityAttributes {
    static var preview: WorkoutActivityAttributes {
        WorkoutActivityAttributes(workoutTypeRawValue: "A")
    }
}

extension WorkoutActivityAttributes.ContentState {
    static var resting: Self {
        .init(
            currentExerciseName: "Bench Press",
            completedSets: 3,
            totalSets: 5,
            nextExerciseName: "Barbell Row",
            restStartDate: .now.addingTimeInterval(-62),
            restEndDate: .now.addingTimeInterval(88),
            workoutTypeLabel: "A",
            targetWeightLabel: "185 lb",
            setReps: [5, 5, 3, nil, nil],
            targetReps: 5,
            restDuration: 150
        )
    }

    static var lifting: Self {
        var state = Self.resting
        state.restStartDate = nil
        state.restEndDate = nil
        state.restDuration = nil
        return state
    }
}

#Preview("Lock screen", as: .content, using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState.resting
    WorkoutActivityAttributes.ContentState.lifting
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState.resting
    WorkoutActivityAttributes.ContentState.lifting
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState.resting
    WorkoutActivityAttributes.ContentState.lifting
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState.resting
    WorkoutActivityAttributes.ContentState.lifting
}
