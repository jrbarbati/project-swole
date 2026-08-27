import SwiftUI

struct RepPickerSheet: View {
    let exerciseName: String
    let setNumber: Int
    let targetReps: Int
    let current: Int?
    /// `nil` clears the set.
    let onPick: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 7) {
                    MetaLabel(text: "\(exerciseName) · set \(setNumber)").tracking(1.6)
                    Text("How many reps?")
                        .font(Theme.Font.display(22))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                MetaLabel(text: "Target \(targetReps)", color: Theme.textDim)
            }

            HStack(spacing: 8) {
                ForEach(0...targetReps, id: \.self) { value in
                    Button {
                        onPick(value)
                        dismiss()
                    } label: {
                        Text("\(value)")
                            .font(Theme.Font.numeric(value == current ? 27 : 24))
                            .foregroundStyle(value == current ? Theme.accentText : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 68)
                            .background(
                                value == current ? Theme.accent.opacity(0.2) : Theme.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .stroke(value == current ? Theme.accent.opacity(0.6) : Theme.border,
                                            lineWidth: value == current ? 1.5 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 20)

            HStack {
                MetaLabel(text: "Tap a number", color: Theme.textDim)
                Spacer()
                Button {
                    onPick(nil)
                    dismiss()
                } label: {
                    Text("Clear set")
                        .font(Theme.Font.body(15))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                                .stroke(Theme.borderStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .background(Theme.canvas)
        .presentationDragIndicator(.visible)
    }
}
