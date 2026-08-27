import SwiftUI

struct RepPickerSheet: View {
    let exerciseName: String
    let setNumber: Int
    let targetReps: Int
    let currentReps: Int?
    /// `nil` clears the set.
    let onPick: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            repButtons
                .padding(.top, 20)

            footer
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .background(Theme.canvas)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
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
    }

    private var repButtons: some View {
        HStack(spacing: 8) {
            ForEach(0...targetReps, id: \.self) { reps in
                repButton(reps)
            }
        }
    }

    private func repButton(_ reps: Int) -> some View {
        let isSelected = reps == currentReps
        return Button {
            onPick(reps)
            dismiss()
        } label: {
            Text("\(reps)")
                .font(Theme.Font.numeric(isSelected ? 27 : 24))
                .foregroundStyle(isSelected ? Theme.accentText : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(
                    isSelected ? Theme.accent.opacity(0.2) : Theme.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .stroke(isSelected ? Theme.accent.opacity(0.6) : Theme.border,
                                lineWidth: isSelected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
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
    }
}
