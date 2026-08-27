import SwiftUI
import SwiftData
import SwoleData

struct HistoryListView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var finishedSessions: [WorkoutSession]

    var body: some View {
        List(finishedSessions) { session in
            NavigationLink {
                HistorySessionDetailView(session: session)
            } label: {
                VStack(alignment: .leading) {
                    Text("Workout \(session.workoutType.rawValue) — \(session.startedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.headline)
                    Text(summary(for: session))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("History")
    }

    private func summary(for session: WorkoutSession) -> String {
        session.exerciseLogs
            .sorted { $0.order < $1.order }
            .map { log in "\(log.exercise?.name ?? "?") \(log.succeeded ? "✓" : "✗")" }
            .joined(separator: " · ")
    }
}
