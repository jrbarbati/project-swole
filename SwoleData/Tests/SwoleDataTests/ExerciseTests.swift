import Testing
import SwiftData
@testable import SwoleData

@Test func exerciseCanBeInsertedAndFetched() throws {
    let container = try ModelContainer(
        for: Exercise.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    context.insert(Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Exercise>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.name == "Squat")
    #expect(fetched.first?.defaultSetCount == 5)
    #expect(fetched.first?.defaultRepsPerSet == 5)
}
