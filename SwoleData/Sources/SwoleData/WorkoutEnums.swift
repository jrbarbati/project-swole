public enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
}

public enum MeasurementUnit: String, Codable, CaseIterable, Sendable {
    case lb
    case kg
}
