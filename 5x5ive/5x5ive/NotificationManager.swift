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

    private init() {}

    /// No-ops if `restEndDate` has already elapsed, or if notification
    /// permission is denied.
    func scheduleRestComplete(restEndDate: Date, body: String) async {
        guard let seconds = RestNotificationPlanner.secondsUntilFire(restEndDate: restEndDate, now: .now) else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: restRequestID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelRestComplete() {
        center.removePendingNotificationRequests(withIdentifiers: [restRequestID])
        center.removeDeliveredNotifications(withIdentifiers: [restRequestID])
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
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
