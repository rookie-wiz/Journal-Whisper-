//
//  ReflectionEngine.swift
//  Journal-Whisper
//
//  The seam between the app and whatever produces moods and reflection prompts.
//  Views and the coordinator only see this protocol, so the on-device model,
//  the offline fallback and test mocks are interchangeable.
//

import Foundation

/// A mood suggestion for an entry.
nonisolated struct MoodResult: Sendable, Equatable {
    let mood: Mood
    /// Within `Mood.intensityRange`.
    let intensity: Int
    /// `.ai` or `.heuristic`; never `.user`.
    let source: MoodSource
}

nonisolated protocol ReflectionEngine: Sendable {
    /// Suggests a mood for the entry text, or nil if there isn't enough signal to say.
    func analyzeMood(_ text: String) async throws -> MoodResult?

    /// Returns a few open-ended reflection prompts for the entry.
    /// `mood` is the entry's current mood, if any; the text may be empty.
    func prompts(for text: String, mood: Mood?) async throws -> [String]

    /// Starts loading the model so the first request is fast. Optional.
    func prewarm()
}

nonisolated extension ReflectionEngine {
    func prewarm() {}
}

nonisolated enum ReflectionError: Error, Equatable {
    /// The entry suggests the writer may be in crisis. Don't generate anything;
    /// show supportive resources instead.
    case needsSupport
    /// The engine couldn't produce a result. Callers fall back to the offline engine.
    case generationFailed(GenerationFailure)
}

/// Why generation failed, without any entry content. Safe to log.
nonisolated enum GenerationFailure: String, Equatable, Sendable {
    /// Model not available on this device, not enabled, or still downloading.
    case unavailable
    /// The model's safety guardrails blocked the input or output.
    case guardrail
    /// The model declined to answer.
    case refusal
    /// The entry was too long for the model's context window.
    case contextTooLong
    /// The entry's language isn't supported by the model.
    case unsupportedLanguage
    /// Too many requests, or another request was running.
    case busy
    case timeout
    case other
}

nonisolated enum ReflectionDefaults {
    /// How many prompts to show at once.
    static let promptCount = 3
    /// Entries shorter than this aren't mood-tagged automatically; there's too little to go on.
    static let minimumWordsForMood = 20
}
