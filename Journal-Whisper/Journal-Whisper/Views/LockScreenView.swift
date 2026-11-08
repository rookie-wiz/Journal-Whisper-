//
//  LockScreenView.swift
//  Journal-Whisper
//
//  Created by shubh on 03/11/26.
//

import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Journal Whisper")
                    .font(.largeTitle.bold())
                Text("Your journal is locked.")
                    .foregroundStyle(.secondary)
            }

            if let message = appLock.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button {
                Task { await appLock.unlock() }
            } label: {
                Label(unlockTitle, systemImage: unlockIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appLock.isAuthenticating)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
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
        case .faceID: "Unlock with Face ID"
        case .touchID: "Unlock with Touch ID"
        case .opticID: "Unlock with Optic ID"
        default: "Unlock with Passcode"
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
