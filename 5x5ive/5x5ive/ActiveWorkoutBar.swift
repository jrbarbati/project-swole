import SwiftUI
import SwoleData

/// Mini "now playing"-style summary shown across every tab while a workout
/// is active but minimized (its `ActiveWorkoutView` is dismissed). Tapping
/// it re-presents the full workout.
struct ActiveWorkoutBar: View {
    let session: WorkoutSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Workout \(session.workoutType.rawValue)")
                            .font(Theme.Font.title(15))
                            .foregroundStyle(Theme.textPrimary)
                        ElapsedLabel(since: session.startedAt)
                    }
                    MetaLabel(text: "\(session.loggedSetCount)/\(session.totalSetCount) sets", color: Theme.textDim)
                }
                Spacer()
                if let end = session.restEndDate {
                    restCountdown(endDate: end)
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, Theme.Space.screenTight)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activeWorkoutBar")
    }

    private func restCountdown(endDate: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endDate.timeIntervalSince(context.date).rounded(.up)))
            // The Group (not the Text inside it) is the stable view identity
            // across ticks — the Text disappears entirely once remaining
            // hits 0, so the haptic trigger must live on a container that's
            // always present to see that transition, mirroring RestBar's
            // pattern of attaching `.sensoryFeedback` to the always-rendered
            // outer container rather than to content that comes and goes.
            Group {
                if remaining > 0 {
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(Theme.Font.numeric(17))
                        .foregroundStyle(Theme.accentText)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityIdentifier("activeWorkoutBarRestCountdown")
                }
            }
            // Rest reaching zero is the one moment the lifter is not looking
            // at the screen.
            .sensoryFeedback(.success, trigger: remaining == 0)
        }
    }
}
