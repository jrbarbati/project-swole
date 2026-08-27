import Testing
import SwiftData
@testable import SwoleData

@Test func userSettingsStoresUnitAndLastWorkoutType() throws {
    let container = try ModelContainer(
        for: UserSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let settings = UserSettings(unit: .lb, lastCompletedWorkoutType: nil)
    context.insert(settings)
    try context.save()

    settings.lastCompletedWorkoutType = .a
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<UserSettings>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.unit == .lb)
    #expect(fetched.first?.lastCompletedWorkoutType == .a)
}
