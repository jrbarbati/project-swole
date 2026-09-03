import AppIntents
import Combine
import Foundation

/// Buttons in a Live Activity run as `LiveActivityIntent` in the APP's
/// process, not the extension's — the only reason they can touch SwiftData.
/// The system launches the app in the background first if it isn't running.
///
/// Must be in both targets' Sources phase, like `WorkoutActivityAttributes`:
/// the extension needs the type to build the button, the app to run it.

struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Rest"
    static var description = IntentDescription("Ends the running rest timer.")
    /// The phone is on the floor next to the bar — the app must not come
    /// to the foreground.
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await WorkoutIntentBus.shared.send(.skipRest)
        return .result()
    }
}

/// No button uses this yet — it shares the bus with Skip at no cost, so it's
/// wired ahead of time. Leave it unattached until a surface needs it.
struct LogSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Set"
    static var description = IntentDescription("Logs the next set at its target reps.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await WorkoutIntentBus.shared.send(.logNextSetAtTarget)
        return .result()
    }
}

/// An intent has no reference to `ActiveWorkoutView`'s `viewModel` or
/// `modelContext`, so it hands off to this singleton, which the view
/// applies. `pending` covers the cold-launch race where the system runs the
/// intent before the view has subscribed.
///
/// Compiled into both targets, but only meaningfully driven from the app
/// process — `ActiveWorkoutView` is what calls `subscribe`/`unsubscribe`.
@MainActor
final class WorkoutIntentBus: ObservableObject {
    static let shared = WorkoutIntentBus()

    enum Action { case skipRest, logNextSetAtTarget }

    /// Set by `ActiveWorkoutView.onAppear`; cleared on disappear.
    private var handler: ((Action) -> Void)?
    private var pending: Action?

    private init() {}

    func send(_ action: Action) {
        guard let handler else {
            pending = action
            return
        }
        handler(action)
    }

    func subscribe(_ handler: @escaping (Action) -> Void) {
        self.handler = handler
        if let pending {
            self.pending = nil
            handler(pending)
        }
    }

    func unsubscribe() {
        handler = nil
    }
}
