import SwiftUI
import SwoleData

struct SetButtonView: View {
    let set: SetLog
    let isEditable: Bool
    let action: () -> Void

    private var label: String {
        guard let reps = set.repsCompleted else { return "—" }
        return "\(reps)"
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.title3.monospacedDigit())
                .frame(width: 48, height: 48)
                .background(set.repsCompleted == nil ? Color.gray.opacity(0.2) : Color.accentColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!isEditable)
    }
}

#Preview {
    SetButtonView(set: SetLog(exerciseLog: nil, setNumber: 1, repsCompleted: nil), isEditable: true, action: {})
}
