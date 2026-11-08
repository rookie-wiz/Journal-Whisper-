//
//  AppLock.swift
//  Journal-Whisper
//

import Foundation
import LocalAuthentication
import Observation

/// Guards the journal behind Face ID / Touch ID, falling back to the device passcode.
@Observable
final class AppLock {
    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    var errorMessage: String?

    /// Set when the app locks; the lock screen consumes it to auto-prompt once
    /// when the app becomes active, so a cancelled prompt doesn't re-trigger in a loop.
    var shouldAutoPrompt = true

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    func lock() {
        isUnlocked = false
        shouldAutoPrompt = true
    }

    #if DEBUG
    /// UI tests launch with `-uiTesting`; skip the system prompt so they can drive the app.
    private let skipAuthForUITests = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    #else
    private let skipAuthForUITests = false
    #endif

    func unlock() async {
        guard !isUnlocked, !isAuthenticating else { return }
        if skipAuthForUITests { isUnlocked = true; return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var policyError: NSError?

        // .deviceOwnerAuthentication = biometrics with passcode fallback.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            if policyError?.code == LAError.passcodeNotSet.rawValue {
                // No passcode on the device means there is nothing to authenticate against.
                isUnlocked = true
                errorMessage = nil
            } else {
                errorMessage = policyError?.localizedDescription ?? "Authentication is unavailable."
            }
            return
        }

        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your journal"
            )
            isUnlocked = true
            errorMessage = nil
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Asks for Face ID / Touch ID (or passcode) to confirm a sensitive action,
    /// such as permanently deleting entries. Doesn't change the lock state.
    /// Returns true only if the user authenticated successfully.
    func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        if skipAuthForUITests { return true }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // Same rule as unlock(): without a device passcode there's nothing to check against.
            return policyError?.code == LAError.passcodeNotSet.rawValue
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
