import SwiftUI
import SwiftData
import SwoleData

@main
struct _x5iveApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = swoleSchema
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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
