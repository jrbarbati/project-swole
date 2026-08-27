public enum WorkoutScheduler {
    
    public static func nextWorkoutType(after settings: UserSettings) -> WorkoutType {
        switch settings.lastCompletedWorkoutType {
        case .none: return .a
        case .a: return .b
        case .b: return .a
        }
    }
}
