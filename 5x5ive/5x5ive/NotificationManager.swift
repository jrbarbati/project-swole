import UserNotifications
import SwoleData

/// Schedules/cancels the single local notification that fires when a rest
/// timer completes while the app isn't in the foreground. Mirrors
/// `HealthKitManager`'s shape: a `@MainActor` singleton wrapping a system
/// framework, authorization requested lazily, every failure swallowed — a
/// missed rest notification is not a crash-worthy event.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let restRequestID = "rest-timer-complete"

    /// Bumped by `cancelRestComplete()` so an in-flight `scheduleRestComplete`
    /// call can detect it was cancelled out from under it and abort before
    /// actually scheduling — guards a fast background→active flip.
    private var generation = 0

    private init() {}

    /// No-ops if `restEndDate` has already elapsed, or if notification
    /// permission isn't already granted. Never prompts for permission itself
    /// — this is called from the background-scheduling path, and iOS can't
    /// present a permission alert to a backgrounded app. Permission must
    /// already have been resolved via `requestAuthorizationIfNeeded()` from a
    /// foreground moment.
    func scheduleRestComplete(restEndDate: Date, body: String) async {
        let requestedGeneration = generation
        guard RestNotificationPlanner.secondsUntilFire(restEndDate: restEndDate, now: .now) != nil else {
            return
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            break
        default:
            return
        }

        guard let seconds = RestNotificationPlanner.secondsUntilFire(restEndDate: restEndDate, now: .now) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Rest Time is Over"
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: restRequestID, content: content, trigger: trigger)
        
        guard generation == requestedGeneration else {
            return
        }
        
        try? await center.add(request)
    }

    func cancelRestComplete() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [restRequestID])
        center.removeDeliveredNotifications(withIdentifiers: [restRequestID])
    }

    /// Resolves notification permission. Must only be called from a
    /// foreground moment (e.g. when a rest timer starts while the app is
    /// active) so the system permission prompt, if needed, has a foregrounded
    /// app to present over.
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }
}
