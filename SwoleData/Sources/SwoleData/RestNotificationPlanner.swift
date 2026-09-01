import Foundation

/// Pure decision logic for whether a rest-complete local notification
/// should be scheduled — kept separate from `UNUserNotificationCenter` so
/// it's testable without a notification-center mock.
public enum RestNotificationPlanner {
    /// `nil` if `restEndDate` is not strictly in the future relative to `now`.
    public static func secondsUntilFire(restEndDate: Date, now: Date) -> TimeInterval? {
        let interval = restEndDate.timeIntervalSince(now)
        return interval > 0 ? interval : nil
    }
}
