import ActivityKit
import Foundation

/// Owns the single Live Activity this app ever runs at a time, showing the
/// active workout's current exercise, its set progress, the next exercise,
/// and a rest countdown when one is running. Mirrors
/// `NotificationManager`'s shape: a `@MainActor` singleton wrapping a
/// system framework, every failure swallowed — an unavailable or denied
/// Live Activity is not crash-worthy.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<WorkoutActivityAttributes>?

    private init() {}

    /// Adopts whatever system Activity already exists (there is ever at
    /// most one, per the app's one-active-session invariant) and pushes
    /// fresh state to it; otherwise starts a new one. Covers a fresh
    /// workout start, reopening a minimized workout, and an app relaunch
    /// with an existing active session, all from one call site
    /// (`ActiveWorkoutView.onAppear`).
    func startIfNeeded(workoutTypeRawValue: String, state: WorkoutActivityAttributes.ContentState) {
        if let existing = Activity<WorkoutActivityAttributes>.activities.first {
            currentActivity = existing
            update(state: state)
            return
        }
        guard currentActivity == nil else { return }

        let attributes = WorkoutActivityAttributes(workoutTypeRawValue: workoutTypeRawValue)
        let content = ActivityContent(state: state, staleDate: staleDate(for: state))
        currentActivity = try? Activity.request(attributes: attributes, content: content)
    }

    func update(state: WorkoutActivityAttributes.ContentState) {
        guard let currentActivity else { return }
        let content = ActivityContent(state: state, staleDate: staleDate(for: state))
        Task { await currentActivity.update(content) }
    }

    func end() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// A rest window re-arms the stale date a couple minutes past its own
    /// end; otherwise a 10-minute fixed buffer, re-armed on every update —
    /// so an actively-updating workout never goes stale (including normal
    /// gaps like pre-first-set setup time or a minimized workout, which
    /// gets no updates until it's reopened), while one whose app process
    /// died stops getting re-armed and dims on schedule.
    private func staleDate(for state: WorkoutActivityAttributes.ContentState) -> Date {
        if let restEnd = state.restEndDate {
            return restEnd.addingTimeInterval(120)
        }
        return Date.now.addingTimeInterval(600)
    }
}
