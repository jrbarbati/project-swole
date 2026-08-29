import Foundation

public enum RestDayCalculator {
    /// A day reads as a rest day once training has started and stays that
    /// way: no workout was trained that day, but some earlier day was
    /// trained. There's no "un-resting" — a day already qualifying as rest
    /// keeps qualifying regardless of what day it's viewed from, including
    /// today.
    public static func isRestDay(_ day: Date, sessionDates: [Date], calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        let trained = sessionDates.contains { calendar.isDate($0, inSameDayAs: dayStart) }
        guard !trained else { return false }
        return sessionDates.contains { $0 < dayStart }
    }
}
