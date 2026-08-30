#if canImport(HealthKit) && os(iOS)
import HealthKit
import SwoleData

@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var energyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var workoutObjectType: HKSampleType { HKObjectType.workoutType() }

    /// Read (body mass) permission is never queryable — HealthKit hides it
    /// for privacy. Write (workout) permission is queryable and stands in as
    /// the connected/not-connected signal shown in Settings.
    enum ConnectionStatus {
        case notDetermined
        case connected
        case denied
    }

    var connectionStatus: ConnectionStatus {
        switch store.authorizationStatus(for: workoutObjectType) {
        case .sharingAuthorized: .connected
        case .sharingDenied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// Shows the system permission sheet if it hasn't been resolved yet;
    /// no-ops silently if already granted, denied, or unavailable. Callable
    /// both from the workout-finish path and from a manual "Connect to
    /// Apple Health" affordance in Settings.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(
                toShare: [workoutObjectType, energyType],
                read: [bodyMassType]
            )
            return true
        } catch {
            return false
        }
    }

    /// Best-effort: writes one Health workout for a finished session. Every
    /// failure (unavailable, denied, no data) is swallowed — Health sync is a
    /// side effect that must never surface an error to the workout-finish flow.
    func saveWorkout(start: Date, end: Date) async {
        guard await requestAuthorization() else { return }

        let energy = await latestBodyWeightKg().map {
            WorkoutEnergyEstimate.kilocalories(bodyWeightKg: $0, duration: end.timeIntervalSince(start))
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: start)
            if let energy {
                let sample = HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                    start: start,
                    end: end
                )
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            return
        }
    }

    private func latestBodyWeightKg() async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }
            store.execute(query)
        }
    }
}
#endif
