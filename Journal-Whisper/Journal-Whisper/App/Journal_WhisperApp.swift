//
//  Journal_WhisperApp.swift
//  Journal-Whisper
//
//  Created by shubh on 02/11/26.
//

import SwiftUI
import SwiftData

@main
struct Journal_WhisperApp: App {
    @State private var appLock = AppLock()

    /// Built once per launch; views read it from the environment.
    private let reflectionEngine: any ReflectionEngine = {
        #if DEBUG
        ReflectionEngineFactory.makeForLaunch()
        #else
        ReflectionEngineFactory.makeDefault()
        #endif
    }()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            JournalEntry.self,
        ])
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        #else
        let inMemory = false
        #endif
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            #if DEBUG
            DebugSeed.apply(to: container)
            #endif
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if DEBUG
        DebugSeed.redirectLogIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appLock)
                .environment(\.reflectionEngine, reflectionEngine)
        }
        .modelContainer(sharedModelContainer)
    }
}
