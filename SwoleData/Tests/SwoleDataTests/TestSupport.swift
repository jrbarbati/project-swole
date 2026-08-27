import SwiftData
@testable import SwoleData

func makeInMemoryContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: swoleSchema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}
