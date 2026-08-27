import SwiftUI
import SwiftData
import SwoleData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]
    @Query(sort: \WorkoutTemplateExercise.order) private var templateEntries: [WorkoutTemplateExercise]
    @State private var startError: String?

    private var settings: UserSettings? { settingsList.first }

    private var nextWorkoutType: WorkoutType {
        guard let settings else { return .a }
        return WorkoutScheduler.nextWorkoutType(after: settings)
    }

    private var nextExercises: [WorkoutTemplateExercise] {
        templateEntries.filter { $0.workoutType == nextWorkoutType }
    }

    var body: some View {
        List {
            Section("Next Workout") {
                Text("Workout \(nextWorkoutType.rawValue)")
                    .font(.title2.bold())
                ForEach(nextExercises) { entry in
                    Text(entry.exercise?.name ?? "Unknown Exercise")
                }
                Button("Start Workout") {
                    startWorkout()
                }
                .disabled(settings == nil)
            }

            Section {
                NavigationLink("History") {
                    HistoryListView()
                }
            }

            if let startError {
                Text(startError)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("5x5ive")
    }

    private func startWorkout() {
        do {
            _ = try WorkoutSessionService.startWorkout(in: modelContext)
        } catch {
            startError = "Couldn't start workout: \(error.localizedDescription)"
        }
    }
}
