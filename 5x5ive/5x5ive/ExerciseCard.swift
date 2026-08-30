import SwiftUI
import SwiftData
import SwoleData

struct ExerciseCard: View {
    let log: ExerciseLog
    let config: UserExerciseConfig?
    let unit: MeasurementUnit
    let isExpanded: Bool
    let onTapSet: (SetLog) -> Void
    let onHoldSet: (SetLog) -> Void
    let onExpand: () -> Void
    let onShowDetail: () -> Void

    @State private var lastSessionSummary: String?

    private var isComplete: Bool { !log.hasUnloggedSets }

    private var plates: PlateMath {
        PlateCalculator.plates(
            for: unit.fromLb(log.targetWeight),
            barWeight: PlateCalculator.barWeight(for: unit),
            available: PlateCalculator.plateSet(for: unit)
        )
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        .background(
            (isExpanded ? Theme.surfaceActive : Color.clear),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(isExpanded ? Theme.borderStrong : Theme.hairline, lineWidth: 1)
        )
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    // MARK: Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            expandedHeader

            SetTileRow(
                log: log,
                onTap: onTapSet,
                onHold: onHoldSet
            )

            expandedFooter
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Theme.Space.cardPadding)
        .task { await loadLastSession() }
    }

    private var expandedHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(log.exercise?.name ?? "")
                .font(Theme.Font.display(19))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                weightReadout
                // Plate math is never hidden — it is the number the lifter
                // needs while standing at the rack.
                Text(plates.shortDescription)
                    .font(Theme.Font.label())
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private var weightReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(unit.fromLb(log.targetWeight).formattedWeight)
                .font(Theme.Font.numeric(16))
                .foregroundStyle(Theme.textPrimary)
            Text(unit.rawValue.uppercased())
                .font(Theme.Font.label(11))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var expandedFooter: some View {
        HStack {
            if let missedSetLabel {
                MetaLabel(text: missedSetLabel, color: Theme.miss).tracking(1.2)
            } else {
                MetaLabel(text: lastSessionSummary ?? " ", color: Theme.textDim).tracking(1.2)
            }
            Spacer()
            Button(action: onShowDetail) {
                MetaLabel(text: "More")
                    .tracking(1.2)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .stroke(Theme.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    /// "SET 4 MISSED · LONGER REST" — explains why rest just got longer.
    private var missedSetLabel: String? {
        guard let missed = log.sortedSets.last(where: { ($0.repsCompleted ?? log.targetReps) < log.targetReps })
        else { return nil }
        return "Set \(missed.setNumber) missed · longer rest"
    }

    // MARK: Collapsed

    private var collapsedBody: some View {
        Button(action: onExpand) {
            HStack {
                HStack(spacing: 10) {
                    if isComplete {
                        completionDot
                    }
                    Text(log.exercise?.name ?? "")
                        .font(Theme.Font.title(isComplete ? 17 : 19))
                        .foregroundStyle(isComplete ? Theme.textMuted : Theme.textSecondary)
                }
                Spacer()
                collapsedReadout
            }
            .padding(.vertical, 14)
            .padding(.horizontal, Theme.Space.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var completionDot: some View {
        Circle()
            .fill(Theme.accent.opacity(0.2))
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Theme.accentStroke, lineWidth: 1))
    }

    @ViewBuilder
    private var collapsedReadout: some View {
        if isComplete {
            Text("\(unit.fromLb(log.targetWeight).formattedWeight) · \(log.repsSummary)")
                .font(Theme.Font.numeric(13))
                .foregroundStyle(Theme.textDim)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(unit.fromLb(log.targetWeight).formattedWeight)
                    .font(Theme.Font.numeric(16))
                Text(unit.rawValue.uppercased())
                    .font(Theme.Font.label(11))
            }
            .foregroundStyle(Theme.textDim)
        }
    }

    // MARK: Data

    /// "LAST 130 · 5 5 5 5 5". Reads the most recent finished log for this lift.
    @MainActor
    private func loadLastSession() async {
        guard lastSessionSummary == nil, let exercise = log.exercise else { return }
        if let previous = try? ProgressionCalculator.previousLog(for: exercise, before: log) {
            lastSessionSummary = "Last \(unit.fromLb(previous.targetWeight).formattedWeight) · \(previous.repsSummary)"
        } else {
            lastSessionSummary = "First time at this lift"
        }
    }
}

// MARK: - Set tile row

struct SetTileRow: View {
    let log: ExerciseLog
    let onTap: (SetLog) -> Void
    let onHold: (SetLog) -> Void

    /// The first unlogged set — the only tile with a focus ring.
    private var nextSetID: PersistentIdentifier? {
        log.sortedSets.first { $0.repsCompleted == nil }?.persistentModelID
    }

    var body: some View {
        HStack(spacing: Theme.Space.tileGap) {
            ForEach(log.sortedSets) { set in
                SetTile(
                    reps: set.repsCompleted,
                    targetReps: log.targetReps,
                    isNext: set.persistentModelID == nextSetID
                )
                .onTapGesture { onTap(set) }
                .onLongPressGesture(minimumDuration: 0.35) { onHold(set) }
                .accessibilityLabel("Set \(set.setNumber)")
                .accessibilityValue(set.repsCompleted.map { "\($0) reps" } ?? "not logged")
                .accessibilityHint("Tap to cycle reps down. Touch and hold to pick a number.")
            }
        }
    }
}
