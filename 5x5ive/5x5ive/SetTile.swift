import SwiftUI

struct SetTile: View {
    let reps: Int?
    let targetReps: Int
    let isNext: Bool

    @State private var breathing = false

    private enum TileState { case next, success, miss, empty }

    private var state: TileState {
        guard let reps else { return isNext ? .next : .empty }
        return reps >= targetReps ? .success : .miss
    }

    private var fill: Color {
        switch state {
        case .success: Theme.accentFill
        case .miss: Theme.missFill
        case .next: Theme.surfaceSunken.opacity(0.9)
        case .empty: Theme.surfaceSunken
        }
    }

    private var stroke: Color {
        switch state {
        case .success: Theme.accentStroke
        case .miss: Theme.missStroke
        case .next: Theme.borderFocus
        case .empty: Theme.border
        }
    }

    private var strokeWidth: CGFloat { state == .next ? 1.5 : 1 }

    private var textColor: Color {
        switch state {
        case .success: Theme.accentText
        case .miss: Theme.miss
        case .next: Theme.textMuted
        case .empty: Theme.textFaint
        }
    }

    private var label: String {
        guard let reps else { return "–" }
        return "\(reps)"
    }

    var body: some View {
        Text(label)
            .font(Theme.Font.numeric(22))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .frame(minWidth: Theme.minTouchTarget, minHeight: Theme.minTouchTarget)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .stroke(stroke, lineWidth: strokeWidth)
            )
            .opacity(state == .next && breathing ? 0.55 : 1)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: breathing)
            .onAppear { if state == .next { breathing = true } }
            .onChange(of: state) { _, newValue in breathing = (newValue == .next) }
            // Digits change on tap; the transition keeps the change legible
            // without moving the tile.
            .contentTransition(.numericText())
            .sensoryFeedback(.impact(weight: .light), trigger: reps)
    }
}

#Preview {
    HStack(spacing: 7) {
        SetTile(reps: 5, targetReps: 5, isNext: false)
        SetTile(reps: 5, targetReps: 5, isNext: false)
        SetTile(reps: 3, targetReps: 5, isNext: false)
        SetTile(reps: nil, targetReps: 5, isNext: true)
        SetTile(reps: nil, targetReps: 5, isNext: false)
    }
    .padding()
    .background(Theme.canvas)
}
