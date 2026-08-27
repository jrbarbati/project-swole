import SwiftUI
import SwoleData

struct RestTimerBanner: View {
    let rest: ActiveWorkoutViewModel.ActiveRest

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(rest.endDate.timeIntervalSince(context.date).rounded(.up)))
            if remaining > 0 {
                HStack {
                    Text(rest.outcome == .success ? "Rest" : "Rest — reset for next attempt")
                    Spacer()
                    Text("\(remaining)s")
                        .monospacedDigit()
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    RestTimerBanner(rest: .init(outcome: .success, endDate: .now.addingTimeInterval(90)))
}
