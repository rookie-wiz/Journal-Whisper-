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
    /// Why the model's answer wasn't used, when the offline engine stepped in.
    var fallbackReason: GenerationFailure? = nil
}

/// Where a result came from.
nonisolated enum Provenance: String, Sendable, Equatable {
    case ai
    case offline
}

/// Reflection prompts plus where they came from, so the UI can say so calmly
/// when they're general rather than personalised.
nonisolated struct PromptSet: Sendable, Equatable {
    let prompts: [String]
    let source: Provenance
    /// Why the model's prompts weren't used, when the offline engine stepped in.
    var fallbackReason: GenerationFailure? = nil
}

nonisolated protocol ReflectionEngine: Sendable {
    /// Suggests a mood for the entry text, or nil if there isn't enough signal to say.
    func analyzeMood(_ text: String) async throws -> MoodResult?

    /// Returns a few open-ended reflection prompts for the entry.
    /// `mood` is the entry's current mood, if any; the text may be empty.
    func prompts(for text: String, mood: Mood?) async throws -> PromptSet

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

    /// True when asking again with the same text will fail the same way, so the
    /// model shouldn't be asked again until the text changes.
    var isDeterministic: Bool {
        switch self {
        case .guardrail, .refusal, .contextTooLong, .unsupportedLanguage: true
        case .unavailable, .busy, .timeout, .other: false
        }
    }
}

nonisolated enum ReflectionDefaults {
    /// How many prompts to show at once.
    static let promptCount = 3
    /// Entries shorter than this aren't mood-tagged automatically; there's too little to go on.
    static let minimumWordsForMood = 20
}

nonisolated extension ReflectionError: LocalizedError {
    /// Names the failure kind only, never entry content (shows up in logs and evaluation results).
    var errorDescription: String? {
        switch self {
        case .needsSupport: "needsSupport"
        case .generationFailed(let failure): "generationFailed(\(failure.rawValue))"
        }
    }
}
