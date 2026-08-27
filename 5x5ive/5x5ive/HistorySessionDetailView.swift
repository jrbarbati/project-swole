import SwiftUI
import SwoleData

struct HistorySessionDetailView: View {
    let session: WorkoutSession

    private var sortedLogs: [ExerciseLog] {
        session.exerciseLogs.sorted { $0.order < $1.order }
    }

    var body: some View {
        List(sortedLogs) { log in
            Section(log.exercise?.name ?? "Unknown Exercise") {
                ExerciseSetsView(log: log, isEditable: false, onSetTap: nil)
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .omitted))
    }
}
