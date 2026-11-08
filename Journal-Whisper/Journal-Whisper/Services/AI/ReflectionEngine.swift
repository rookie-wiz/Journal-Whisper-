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
}

nonisolated enum ReflectionError: Error, Equatable {
    /// The entry suggests the writer may be in crisis. Don't generate anything;
    /// show supportive resources instead.
    case needsSupport
}

nonisolated enum ReflectionDefaults {
    /// How many prompts to show at once.
    static let promptCount = 3
}
