import Foundation

/// Body copy for the rest-complete local notification. Picked randomly so
/// repeated notifications don't feel robotic; deliberately independent of
/// the on-screen rest label (which stays informative — "next exercise",
/// "set 3 next") rather than punchy.
public enum RestCompleteMessages {
    public static let all: [String] = [
        "Rest's over. Get back under the bar.",
        "Time's up — next set's waiting.",
        "Rest complete. Go earn it.",
        "Back to work.",
        "That's enough sitting around.",
        "Rested. Ready. Go.",
        "The bar's not getting any lighter.",
        "Next set won't lift itself.",
        "Recovery's done. Reload.",
    ]

    public static func random() -> String {
        all.randomElement()!
    }
}
