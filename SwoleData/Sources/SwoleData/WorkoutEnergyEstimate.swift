import Foundation

public enum WorkoutEnergyEstimate {
    /// MET for free-weight resistance training (moderate-vigorous, ACSM tables).
    public static let strengthTrainingMET = 5.0

    /// kcal = MET * bodyweight(kg) * duration(hours).
    public static func kilocalories(bodyWeightKg: Double, duration: TimeInterval, met: Double = strengthTrainingMET) -> Double {
        met * bodyWeightKg * (duration / 3600)
    }
}
