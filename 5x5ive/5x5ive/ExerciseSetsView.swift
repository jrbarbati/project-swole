import SwiftUI
import SwoleData

struct ExerciseSetsView: View {
    let log: ExerciseLog
    let isEditable: Bool
    let onSetTap: ((SetLog) -> Void)?

    private var sortedSets: [SetLog] {
        log.sets.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(log.targetWeight.formatted()) lb × \(log.targetReps)")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(sortedSets) { set in
                    SetButtonView(set: set, isEditable: isEditable) {
                        onSetTap?(set)
                    }
                }
            }
        }
    }
}

#Preview {
    let log = ExerciseLog(session: nil, exercise: Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5), targetWeight: 135, targetReps: 5, order: 0)
    for n in 1...5 {
        log.sets.append(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n <= 2 ? 5 : nil))
    }
    return ExerciseSetsView(log: log, isEditable: true, onSetTap: nil)
        .padding()
}
