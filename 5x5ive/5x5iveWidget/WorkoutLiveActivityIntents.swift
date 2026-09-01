import AppIntents
import Combine
import Foundation

/// Buttons in a Live Activity run as `LiveActivityIntent`, which executes in
/// the APP's process rather than the extension's — the only reason these can
/// touch SwiftData at all. If the app isn't running, the system launches it
/// in the background first.
///
/// Must be in BOTH targets' Sources build phase (same as
/// `WorkoutActivityAttributes.swift`): the extension needs the type to build
/// the button, the app needs it to execute the action.

struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Rest"
    static var description = IntentDescription("Ends the running rest timer.")
    /// The app must not come to the foreground — the phone is on the floor
    /// next to the bar.
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
/// `modelContext`, so it hands the action to this singleton and the view
/// applies it. `pending` covers the cold-launch case: the system may run the
/// intent before the view has subscribed, and the tap must not be lost.
///
/// Compiled into both targets (like the intents above), but only ever
/// meaningfully driven from the app process — `perform()` runs there, and
/// `ActiveWorkoutView` is what calls `subscribe`/`unsubscribe`.
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
