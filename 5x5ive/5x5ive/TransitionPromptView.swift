import SwiftUI
import SwoleData

struct TransitionPromptView: View {
    let prompt: ActiveWorkoutViewModel.TransitionPrompt
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(prompt.isFinalExercise ? "Workout complete" : "Nice work on \(prompt.exerciseName)")
                .font(.title2.bold())
            Text(prompt.isFinalExercise ? "Tap Finish Workout when you're ready." : "Ready for the next exercise?")
                .foregroundStyle(.secondary)
            Button(prompt.isFinalExercise ? "OK" : "Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

#Preview {
    TransitionPromptView(prompt: .init(exerciseName: "Squat", isFinalExercise: false), onContinue: {})
}
