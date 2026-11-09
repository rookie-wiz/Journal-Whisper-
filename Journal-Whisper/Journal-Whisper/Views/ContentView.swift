//
//  ContentView.swift
//  Journal-Whisper
//
//  Created by shubh on 02/11/26.
//

import SwiftUI
import SwiftData

/// Root view: onboarding on first launch, then the journal only when
/// unlocked; hides the journal from the app switcher.
struct ContentView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Onboarding.completedKey) private var hasCompletedOnboarding = false
    @State private var finishedOnboardingThisLaunch = false

    var body: some View {
        ZStack {
            if Onboarding.shouldShow(completedBefore: hasCompletedOnboarding,
                                     finishedThisLaunch: finishedOnboardingThisLaunch) {
                // Finishing hands over to the lock screen, which asks for Face ID.
                OnboardingView {
                    hasCompletedOnboarding = true
                    withAnimation { finishedOnboardingThisLaunch = true }
                }
                    .transition(.opacity)
            } else if appLock.isUnlocked {
                JournalListView()
            } else {
                LockScreenView()
            }

            // Cover content in the app switcher snapshot.
            if appLock.isUnlocked && scenePhase != .active {
                PrivacyCoverView()
            }
        }
        .tint(Theme.accent)
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
            Rectangle().fill(Theme.background)
            LanternView(brightness: 0.4, showsFace: false, size: 140)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environment(AppLock())
        .environment(MilestoneStore())
        .modelContainer(try! ModelContainer.journal(inMemory: true))
}
