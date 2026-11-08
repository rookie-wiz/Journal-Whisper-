//
//  ContentView.swift
//  Journal-Whisper
//
//  Created by shubh on 02/11/26.
//

import SwiftUI
import SwiftData

/// Root view: shows the journal only when unlocked, and hides it from the app switcher.
struct ContentView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if appLock.isUnlocked {
                JournalListView()
            } else {
                LockScreenView()
            }

            // Cover content in the app switcher snapshot.
            if appLock.isUnlocked && scenePhase != .active {
                PrivacyCoverView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                appLock.lock()
            }
        }
    }
}

private struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environment(AppLock())
        .modelContainer(for: JournalEntry.self, inMemory: true)
}
