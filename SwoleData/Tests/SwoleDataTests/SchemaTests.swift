import Testing
@testable import SwoleData

@Test func fullSchemaBuildsAnInMemoryContainer() throws {
    _ = try makeInMemoryContext()
}
