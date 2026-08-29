import SwiftUI
import SwiftData
import SwoleData

@main
struct _x5iveApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = swoleSchema
        // UI tests pass this to get a clean, seeded store every launch
        // instead of accumulating state across runs.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTestingInMemoryStore")
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let context = ModelContext(container)
            _ = try StandardSeed.seed(in: context)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
