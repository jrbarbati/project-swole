import SwiftUI
import SwiftData
import SwoleData

private struct ResetAppDataKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Wipes the app back to first-launch state by swapping in a brand new,
    /// freshly-seeded ModelContainer rather than deleting rows out from
    /// under it. Other permanently-mounted views (HistoryView,
    /// ActiveWorkoutView) hold live @Query results over the current store;
    /// deleting those rows in place crashes them when they next resolve a
    /// property on a now-detached object. Recreating the container sidesteps
    /// that entirely — nothing ever observes a deleted object because the
    /// whole store, context, and view subtree are replaced together.
    var resetAppData: () -> Void {
        get { self[ResetAppDataKey.self] }
        set { self[ResetAppDataKey.self] = newValue }
    }
}

@main
struct _x5iveApp: App {
    // UI tests pass this to get a clean, seeded store every launch instead
    // of accumulating state across runs.
    private let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTestingInMemoryStore")

    @State private var container: ModelContainer

    init() {
        _container = State(initialValue: Self.makeContainer(inMemory: inMemory))
    }

    var body: some Scene {
        WindowGroup {
            // .id forces a full remount of the view tree on reset, so no
            // stale view node anywhere can still hold a reference into the
            // discarded container.
            RootView()
                .id(ObjectIdentifier(container))
                .environment(\.resetAppData, resetAppData)
        }
        .modelContainer(container)
    }

    private func resetAppData() {
        if !inMemory, let url = container.configurations.first?.url {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        container = Self.makeContainer(inMemory: inMemory)
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let modelConfiguration = ModelConfiguration(schema: swoleSchema, isStoredInMemoryOnly: inMemory)

        do {
            let container = try ModelContainer(for: swoleSchema, configurations: [modelConfiguration])
            let context = ModelContext(container)
            _ = try StandardSeed.seed(in: context)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
