public enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
}

public enum MeasurementUnit: String, Codable, CaseIterable, Sendable {
    case lb
    case kg
}

public extension MeasurementUnit {
    static let kilogramsPerPound = 0.45359237

    /// All weights are stored in pounds; converts to this unit for display.
    func fromLb(_ pounds: Double) -> Double {
        self == .lb ? pounds : pounds * Self.kilogramsPerPound
    }
}
