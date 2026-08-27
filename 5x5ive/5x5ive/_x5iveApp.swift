//
//  _x5iveApp.swift
//  5x5ive
//
//  Created by Joseph Barbati on 8/27/26.
//

import SwiftUI
import SwiftData
import SwoleData

@main
struct _x5iveApp: App {
    var sharedModelContainer: ModelContainer = {
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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
