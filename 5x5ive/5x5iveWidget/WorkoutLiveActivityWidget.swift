import WidgetKit
import SwiftUI
import ActivityKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreenBanner(for: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.currentExerciseName)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingContent(for: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let nextExerciseName = context.state.nextExerciseName {
                        Text("Next: \(nextExerciseName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text(context.state.currentExerciseName)
                    .font(.caption2)
                    .lineLimit(1)
            } compactTrailing: {
                trailingContent(for: context.state)
                    .font(.caption2)
            } minimal: {
                if let restEndDate = context.state.restEndDate {
                    Text(timerInterval: Date.now...restEndDate, countsDown: true)
                        .font(.caption2)
                        .monospacedDigit()
                } else {
                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private func lockScreenBanner(for state: WorkoutActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.currentExerciseName)
                    .font(.headline)
                Spacer()
                Text("\(state.completedSets)/\(state.totalSets) sets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let restStartDate = state.restStartDate, let restEndDate = state.restEndDate {
                Text(timerInterval: restStartDate...restEndDate, countsDown: true)
                    .font(.title2)
                    .monospacedDigit()
            }
            if let nextExerciseName = state.nextExerciseName {
                Text("Next: \(nextExerciseName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func trailingContent(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let restEndDate = state.restEndDate {
            Text(timerInterval: Date.now...restEndDate, countsDown: true)
                .monospacedDigit()
        } else {
            Text("\(state.completedSets)/\(state.totalSets)")
        }
    }
}
