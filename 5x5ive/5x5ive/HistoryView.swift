import SwiftUI
import SwiftData
import SwoleData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt != nil },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var selectedExercise: Exercise?
    @State private var trendLogs: [ExerciseLog] = []

    private var grouped: [(month: String, sessions: [WorkoutSession])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let dict = Dictionary(grouping: sessions) { formatter.string(from: $0.startedAt) }
        return dict
            .sorted { ($0.value.first?.startedAt ?? .distantPast) > ($1.value.first?.startedAt ?? .distantPast) }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("History")
                    .font(Theme.Font.display(34))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, 14)

                trendCard
                    .padding(.top, 22)
                    .padding(.horizontal, Theme.Space.screen)

                ForEach(grouped, id: \.month) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        MetaLabel(text: group.month).tracking(1.6)
                            .padding(.bottom, 10)
                        ForEach(group.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 22)
                    .padding(.horizontal, Theme.Space.screen)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadTrend() }
        .onChange(of: selectedExercise) { _, _ in Task { await loadTrend() } }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel(text: "\(selectedExercise?.name ?? "—") · working weight")
                Spacer()
                if let latest = trendLogs.last?.targetWeight {
                    MetaLabel(text: "\(latest.formatted()) lb", color: Theme.accentText)
                }
            }

            WeightTrendChart(
                logs: trendLogs.dropLast(),
                currentWeight: trendLogs.last?.targetWeight ?? 0
            )
            .frame(height: 76)

            // Lift filter. Horizontal scroll keeps five lifts on one line at
            // any Dynamic Type size.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(exercises) { exercise in
                        Button {
                            selectedExercise = exercise
                        } label: {
                            Text(exercise.name.uppercased())
                                .font(Theme.Font.label(10))
                                .tracking(1)
                                .foregroundStyle(exercise == selectedExercise ? Theme.textPrimary : Theme.textDim)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(
                                    exercise == selectedExercise ? Theme.surfaceSunken : .clear,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    @MainActor
    private func loadTrend() async {
        if selectedExercise == nil { selectedExercise = exercises.first }
        guard let exercise = selectedExercise else { return }
        let recent = (try? ProgressionCalculator.recentLogs(for: exercise, limit: 10, in: modelContext)) ?? []
        trendLogs = recent
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("Workout \(session.workoutType.rawValue)")
                        .font(Theme.Font.title(17))
                        .foregroundStyle(Theme.textPrimary)
                    MetaLabel(text: session.startedAt.formatted(.dateTime.month(.abbreviated).day()),
                              color: Theme.textDim)
                }
                Text(session.sortedLogs
                    .map { "\($0.exercise?.name.uppercased() ?? "?") \($0.targetWeight.formatted())" }
                    .joined(separator: " · "))
                    .font(Theme.Font.label())
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(session.sortedLogs) { log in
                    Circle()
                        .fill(log.succeeded ? Theme.accent : Theme.miss)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}
