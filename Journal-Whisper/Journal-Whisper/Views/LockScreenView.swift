//
//  LockScreenView.swift
//  Journal-Whisper
//
//  Created by shubh on 03/11/26.
//
//  Shows nothing personal (no streak, no counts): nothing private appears
//  before the journal is unlocked.
//

import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 26) {
                LanternView(brightness: 0.6, size: 200)

                VStack(spacing: 10) {
                    Text("Welcome back")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    Text("Your lantern kept your pages safe while you were away.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                if let message = appLock.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()

            Button {
                Task { await appLock.unlock() }
            } label: {
                Label(unlockTitle, systemImage: unlockIcon)
            }
            .buttonStyle(.chunky)
            .disabled(appLock.isAuthenticating)
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
            .accessibilityIdentifier("unlockButton")
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: appLock.isUnlocked) { _, unlocked in unlocked }
        .task { autoPromptIfNeeded() }
        .onChange(of: scenePhase) { _, _ in autoPromptIfNeeded() }
    }

    /// Prompt once per lock, and only while the app is in the foreground.
    private func autoPromptIfNeeded() {
        guard scenePhase == .active, appLock.shouldAutoPrompt else { return }
        appLock.shouldAutoPrompt = false
        Task { await appLock.unlock() }
    }

    private var unlockTitle: String {
        switch appLock.biometryType {
        case .faceID: String(localized: "Open with Face ID")
        case .touchID: String(localized: "Open with Touch ID")
        case .opticID: String(localized: "Open with Optic ID")
        default: String(localized: "Open with Passcode")
        }
    }

    private var unlockIcon: String {
        switch appLock.biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.open"
        }
    }
}

#Preview {
    LockScreenView()
        .environment(AppLock())
}
