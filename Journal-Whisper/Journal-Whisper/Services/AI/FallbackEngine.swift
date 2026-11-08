//
//  FallbackEngine.swift
//  Journal-Whisper
//
//  Tries the primary engine (the on-device model) and quietly falls back to
//  the secondary (the offline heuristic) if it fails for any reason: model
//  unavailable, guardrail, refusal, unsupported language, too long, etc.
//  Crisis detection and cancellation are passed through, never masked.
//

import Foundation
import os

nonisolated struct FallbackEngine: ReflectionEngine {
    let primary: any ReflectionEngine
    let fallback: any ReflectionEngine

    private static let logger = Logger(subsystem: "com.shubh.Journal-Whisper", category: "Reflection")

    func analyzeMood(_ text: String) async throws -> MoodResult? {
        do {
            return try await primary.analyzeMood(text)
        } catch let error where Self.shouldFallBack(from: error) {
            Self.log(error, operation: "mood")
            return try await fallback.analyzeMood(text)
        }
    }

    func prompts(for text: String, mood: Mood?) async throws -> [String] {
        do {
            return try await primary.prompts(for: text, mood: mood)
        } catch let error where Self.shouldFallBack(from: error) {
            Self.log(error, operation: "prompts")
            return try await fallback.prompts(for: text, mood: mood)
        }
    }

    func prewarm() { primary.prewarm() }

    private static func shouldFallBack(from error: any Error) -> Bool {
        if error is CancellationError { return false }
        if let error = error as? ReflectionError, error == .needsSupport { return false }
        return true
    }

    /// Logs only the failure kind; entry text is never logged.
    private static func log(_ error: any Error, operation: StaticString) {
        let kind = (error as? ReflectionError).flatMap { error -> GenerationFailure? in
            if case .generationFailed(let failure) = error { failure } else { nil }
        } ?? .other
        logger.notice("Falling back to offline \(operation, privacy: .public): \(kind.rawValue, privacy: .public)")
    }
}
