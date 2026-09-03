import SwiftUI
import SwoleData

struct RestBar: View {
    let rest: ActiveWorkoutViewModel.ActiveRest?
    let onSkip: () -> Void

    var body: some View {
        Group {
            if let rest {
                countdown(for: rest)
            } else {
                idlePrompt
            }
        }
        .frame(height: 72)
        .animation(.snappy(duration: 0.2), value: rest == nil)
    }

    private func countdown(for rest: ActiveWorkoutViewModel.ActiveRest) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = rest.remaining(at: context.date)
            HStack(spacing: 16) {
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(Theme.Font.numeric(38))
                    .foregroundStyle(Theme.accentText)
                    .contentTransition(.numericText(countsDown: true))

                VStack(alignment: .leading, spacing: 8) {
                    MetaLabel(text: rest.nextUpLabel)
                    // Drains full-to-empty, matching the Live Activity's bar.
                    progressTrack(fraction: 1 - rest.progress(at: context.date))
                }

                skipButton
            }
            .padding(Theme.Space.cardPadding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
            )
            // Rest reaching zero is the one moment the lifter is not looking
            // at the screen.
            .sensoryFeedback(.success, trigger: remaining == 0)
        }
    }

    private func progressTrack(fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.borderStrong)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            MetaLabel(text: "Skip")
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var idlePrompt: some View {
        HStack {
            Text("Tap a set to log · hold to pick reps")
                .font(Theme.Font.body(14))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            MetaLabel(text: "No rest", color: Theme.textDim)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}
