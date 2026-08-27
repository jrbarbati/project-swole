//
//  ContentView.swift
//  5x5ive
//
//  Created by Joseph Barbati on 8/27/26.
//

import SwiftUI
import SwiftData
import SwoleData

struct ContentView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            if let activeSession = activeSessions.first {
                ActiveWorkoutView(session: activeSession)
            } else {
                HomeView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Exercise.self,
            UserExerciseConfig.self,
            WorkoutTemplateExercise.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetLog.self,
            UserSettings.self,
        ], inMemory: true)
}
