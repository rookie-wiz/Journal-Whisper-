//
//  SummaryEngine.swift
//  Journal-Whisper
//
//  Weekly summaries. The facts (days written, moods, trend) always come from
//  code; an engine only writes the words. `TemplateSummaryEngine` is the
//  offline engine: it builds sentences from the statistics alone and never
//  quotes or paraphrases entry text.
//

import Foundation

/// A generated summary, before it's saved.
nonisolated struct SummaryDraft: Sendable, Equatable {
    let text: String
    let source: Provenance
    var fallbackReason: GenerationFailure? = nil
    /// One reflection question for the week ahead. Nil for weeks that need support.
    var closingQuestion: String? = nil
    /// Per-entry notes written along the way, to cache on the entries.
    var gists: [GistKey: String] = [:]
}

/// Identifies the exact version of an entry a gist was written from.
nonisolated struct GistKey: Hashable, Sendable {
    let createdAt: Date
    let updatedAt: Date

    init(createdAt: Date, updatedAt: Date) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(_ entry: EntrySnapshot) {
        self.init(createdAt: entry.createdAt, updatedAt: entry.updatedAt)
    }
}

nonisolated protocol SummaryEngine: Sendable {
    /// Summarises a week with at least one entry.
    func summarize(_ week: WeekSnapshot) async throws -> SummaryDraft
}

nonisolated struct TemplateSummaryEngine: SummaryEngine {

    func summarize(_ week: WeekSnapshot) async throws -> SummaryDraft {
        Self.draft(for: week)
    }

    static func draft(for week: WeekSnapshot) -> SummaryDraft {
        let sentences = [writingSentence(week), moodSentence(week.statistics), trendSentence(week.statistics)]
        return SummaryDraft(
            text: sentences.compactMap { $0 }.joined(separator: " "),
            source: .offline,
            closingQuestion: week.needsSupport ? nil : closingQuestion(for: week)
        )
    }

    // MARK: - Sentences

    static func writingSentence(_ week: WeekSnapshot) -> String {
        let entries = week.entries.count, days = week.daysWritten
        switch (days, entries) {
        case (_, 1): return String(localized: "You wrote once this week.")
        case (1, _): return String(localized: "You wrote \(entries) entries on one day this week.")
        case let (days, entries) where entries > days:
            return String(localized: "You wrote on \(days) days this week, \(entries) entries in all.")
        default: return String(localized: "You wrote on \(days) days this week.")
        }
    }

    static func moodSentence(_ stats: MoodStatistics) -> String {
        let ranked = stats.rankedMoods
        guard let top = ranked.first else {
            return String(localized: "None of this week's entries have a mood yet.")
        }
        // A clear favourite: at least twice, and more than any other.
        if top.count >= 2, ranked.count == 1 || ranked[1].count < top.count {
            return String(localized: "\(top.mood.label) came up most often.")
        }
        let names = ranked.prefix(3).map { $0.mood.label.lowercased() }
        if names.count == 1 {
            return String(localized: "You felt \(names[0]).")
        }
        let list = ListFormatter.localizedString(byJoining: names)
        return String(localized: "Your moods ranged across \(list).")
    }

    static func trendSentence(_ stats: MoodStatistics) -> String? {
        switch stats.trend {
        case .lighter?: String(localized: "Things felt lighter toward the end of the week.")
        case .heavier?: String(localized: "The second half of the week felt heavier.")
        case .steady?: String(localized: "Your mood was fairly steady.")
        case nil: nil
        }
    }

    /// The same question every time the same week is shown.
    static func closingQuestion(for week: WeekSnapshot) -> String? {
        var random = StableRandom(seed: UInt64(bitPattern: Int64(week.week.start.timeIntervalSinceReferenceDate)))
        return PromptBank.pick(for: week.statistics.dominantMood, count: 1, using: &random).first
    }
}

/// SplitMix64: a small deterministic generator, so a week's template question
/// doesn't change every time the Insights screen is opened.
nonisolated struct StableRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
