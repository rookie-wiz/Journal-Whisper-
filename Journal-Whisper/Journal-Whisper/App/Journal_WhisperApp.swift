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
    @State private var milestones: MilestoneStore = {
        #if DEBUG
        // UI tests start each run with no badges.
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return MilestoneStore(defaults: UserDefaults(suiteName: "uiTesting.\(UUID().uuidString)")!)
        }
        #endif
        return MilestoneStore()
    }()

    /// Built once per launch; views read it from the environment.
    private let reflectionEngine: any ReflectionEngine = {
        #if DEBUG
        ReflectionEngineFactory.makeForLaunch()
        #else
        ReflectionEngineFactory.makeDefault()
        #endif
    }()

    private let summaryEngine: any SummaryEngine = {
        #if DEBUG
        SummaryEngineFactory.makeForLaunch()
        #else
        SummaryEngineFactory.makeDefault()
        #endif
    }()

    var sharedModelContainer: ModelContainer = {
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        #else
        let inMemory = false
        #endif

        do {
            let container = try ModelContainer.journal(inMemory: inMemory)
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
                .environment(milestones)
                .environment(\.reflectionEngine, reflectionEngine)
                .environment(\.summaryEngine, summaryEngine)
        }
        .modelContainer(sharedModelContainer)
    }
}
