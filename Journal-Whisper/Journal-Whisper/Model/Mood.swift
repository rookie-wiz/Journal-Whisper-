//
//  Mood.swift
//  Journal-Whisper
//
//  The fixed set of moods an entry can be tagged with. Kept small and closed so
//  the on-device model (Week 2) can only choose from this list, and so mood
//  charts (Week 3) have stable categories.
//

import Foundation

nonisolated enum Mood: String, CaseIterable, Codable, Identifiable {
    case joyful, content, calm, neutral, anxious, sad, frustrated, overwhelmed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .joyful: String(localized: "Joyful")
        case .content: String(localized: "Content")
        case .calm: String(localized: "Calm")
        case .neutral: String(localized: "Neutral")
        case .anxious: String(localized: "Anxious")
        case .sad: String(localized: "Sad")
        case .frustrated: String(localized: "Frustrated")
        case .overwhelmed: String(localized: "Overwhelmed")
        }
    }

    var emoji: String {
        switch self {
        case .joyful: "😄"
        case .content: "🙂"
        case .calm: "😌"
        case .neutral: "😐"
        case .anxious: "😟"
        case .sad: "😢"
        case .frustrated: "😤"
        case .overwhelmed: "😵‍💫"
        }
    }

    /// Valid range for `JournalEntry.moodIntensity`.
    static let intensityRange = 1...5
    static let defaultIntensity = 3
}

/// Who set an entry's mood. A mood the user picked is never replaced by a suggestion.
nonisolated enum MoodSource: String, Codable {
    /// Suggested by the on-device language model.
    case ai
    /// Suggested by the offline keyword fallback.
    case heuristic
    /// Chosen by the user.
    case user
}
