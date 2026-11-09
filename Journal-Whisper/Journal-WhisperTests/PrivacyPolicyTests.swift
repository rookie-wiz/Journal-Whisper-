//
//  PrivacyPolicyTests.swift
//  Journal-WhisperTests
//
//  Keeps PRIVACY.md identical to the in-app policy, and checks the promises
//  the policy makes about the code.
//
//  To regenerate PRIVACY.md after changing PrivacyPolicy.swift:
//    TEST_RUNNER_UPDATE_PRIVACY=1 xcodebuild test ... -only-testing:Journal-WhisperTests/PrivacyPolicyTests
//

import Foundation
import Testing
import SwiftData
@testable import Journal_Whisper

struct PrivacyPolicyTests {

    /// Repo root, found from this file's location.
    private static let privacyFile = URL(filePath: #filePath)
        .deletingLastPathComponent()      // Journal-WhisperTests
        .deletingLastPathComponent()      // Journal-Whisper (project)
        .deletingLastPathComponent()      // repo root
        .appending(path: "PRIVACY.md")

    @Test func markdownFileMatchesTheApp() throws {
        if ProcessInfo.processInfo.environment["UPDATE_PRIVACY"] == "1" {
            try PrivacyPolicy.markdown.write(to: Self.privacyFile, atomically: true, encoding: .utf8)
        }
        let file = try String(contentsOf: Self.privacyFile, encoding: .utf8)
        #expect(file == PrivacyPolicy.markdown, "PRIVACY.md is out of date; regenerate it (see this file's header).")
    }

    @Test func policyCoversTheEssentials() {
        let text = PrivacyPolicy.markdown.lowercased()
        for phrase in ["on-device", "never sends what you write", "backups", "face id", "30 days", "not a medical or crisis service"] {
            #expect(text.contains(phrase), "\(phrase)")
        }
    }

    @Test @MainActor func storeNeverSyncsToICloud() throws {
        let container = try ModelContainer.journal(inMemory: true)
        // CloudKitDatabase isn't Equatable; compare descriptions.
        let none = String(describing: ModelConfiguration.CloudKitDatabase.none)
        let configured = container.configurations.map { String(describing: $0.cloudKitDatabase) }
        #expect(!configured.isEmpty && configured.allSatisfy { $0 == none }, "\(configured)")
    }
}
