//
//  HeuristicEngine.swift
//  Journal-Whisper
//
//  The non-AI fallback. Tags moods by matching a small word list (skipping
//  negated words like "not happy") and picks prompts from `PromptBank`.
//  Fast, predictable and fully offline; used whenever the on-device model
//  isn't available or fails.
//

import Foundation

nonisolated struct HeuristicEngine: ReflectionEngine {

    func analyzeMood(_ text: String) async throws -> MoodResult? {
        Self.classify(text)
    }

    func prompts(for text: String, mood: Mood?) async throws -> PromptSet {
        let mood = mood ?? Self.classify(text)?.mood
        return PromptSet(prompts: PromptBank.pick(for: mood), source: .offline)
    }

    // MARK: - Classification

    /// Synchronous core, also used directly by tests.
    static func classify(_ text: String) -> MoodResult? {
        // Match within clauses so a negator never reaches across punctuation:
        // in "No rush, no plans. Very at ease." the "no" doesn't negate "at ease".
        let clauses = clauses(of: text)
        guard !clauses.isEmpty else { return nil }

        var best: (mood: Mood, hits: Int, intensified: Bool, lastIndex: Int)?
        for mood in Mood.allCases {
            var hits = 0, intensified = false, lastIndex = -1
            for phrase in MoodLexicon.phrases[mood] ?? [] {
                for clause in clauses {
                    for index in matches(of: phrase, in: clause.tokens) where !isNegated(at: index, in: clause.tokens) {
                        hits += 1
                        lastIndex = max(lastIndex, clause.offset + index)
                        if isIntensified(at: index, in: clause.tokens) { intensified = true }
                    }
                }
            }
            guard hits > 0 else { continue }
            // Most hits wins; on a tie, the mood mentioned last (usually how the entry ends up).
            if let current = best, (hits, lastIndex) <= (current.hits, current.lastIndex) { continue }
            best = (mood, hits, intensified, lastIndex)
        }

        guard let best else { return nil }
        return MoodResult(
            mood: best.mood,
            intensity: intensity(hits: best.hits, intensified: best.intensified, text: text),
            source: .heuristic
        )
    }

    /// Tokenized clauses, split on sentence and clause punctuation, with each
    /// clause's position in the whole entry (for the "mentioned last" tie-break).
    static func clauses(of text: String) -> [(tokens: [String], offset: Int)] {
        var offset = 0
        return text.split(whereSeparator: { ".!?;,\n".contains($0) }).compactMap { part in
            let tokens = tokenize(String(part))
            guard !tokens.isEmpty else { return nil }
            defer { offset += tokens.count }
            return (tokens, offset)
        }
    }

    /// Lowercased words, keeping apostrophes so "don't" stays one token.
    static func tokenize(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !($0.isLetter || $0 == "'") }
            .map(String.init)
    }

    /// Start indexes where the (possibly multi-word) phrase occurs.
    private static func matches(of phrase: [String], in tokens: [String]) -> [Int] {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return [] }
        return (0...(tokens.count - phrase.count)).filter { start in
            phrase.indices.allSatisfy { tokens[start + $0] == phrase[$0] }
        }
    }

    /// True if a negator appears within the few words before the match ("not very happy").
    private static func isNegated(at index: Int, in tokens: [String]) -> Bool {
        tokens[max(0, index - MoodLexicon.negationWindow)..<index].contains { MoodLexicon.negators.contains($0) }
    }

    private static func isIntensified(at index: Int, in tokens: [String]) -> Bool {
        tokens[max(0, index - 2)..<index].contains { MoodLexicon.intensifiers.contains($0) }
    }

    /// 1 hit → 2, 2 → 3, 3–4 → 4, 5+ → 5; one step more for "very"/"so"/"!!".
    private static func intensity(hits: Int, intensified: Bool, text: String) -> Int {
        let base = switch hits {
        case 1: 2
        case 2: 3
        case 3...4: 4
        default: 5
        }
        let boost = (intensified || text.contains("!!")) ? 1 : 0
        return min(base + boost, Mood.intensityRange.upperBound)
    }
}

/// Word lists for the fallback classifier. Words are matched whole (no stemming),
/// so each list spells out the common forms. Ambiguous words ("down", "miss")
/// only count inside a phrase.
nonisolated enum MoodLexicon {
    static let phrases: [Mood: [[String]]] = rawPhrases.mapValues { list in
        list.map { $0.split(separator: " ").map(String.init) }
    }

    private static let rawPhrases: [Mood: [String]] = [
        .joyful: [
            "happy", "happier", "happiest", "joy", "joyful", "excited", "exciting", "thrilled",
            "ecstatic", "delighted", "amazing", "wonderful", "fantastic", "awesome", "elated",
            "overjoyed", "celebrate", "celebrated", "celebrating", "great day", "best day",
        ],
        .content: [
            "content", "satisfied", "grateful", "thankful", "glad", "pleased", "fulfilled",
            "proud", "cozy", "comfortable", "appreciate", "appreciated", "blessed", "good day",
        ],
        .calm: [
            "calm", "peaceful", "relaxed", "relaxing", "serene", "rested", "restful", "tranquil",
            "at ease", "slow day", "meditated", "meditation", "unwind", "unwinding", "chill",
        ],
        .neutral: [
            "okay", "fine", "normal", "ordinary", "uneventful", "meh", "alright",
            "nothing much", "nothing special", "same as usual",
        ],
        .anxious: [
            "anxious", "anxiety", "nervous", "worried", "worry", "worrying", "worries",
            "stressed", "stress", "stressful", "uneasy", "scared", "afraid", "panic",
            "panicking", "tense", "restless", "dread", "dreading", "on edge",
        ],
        .sad: [
            "sad", "sadness", "unhappy", "lonely", "cried", "crying", "tears", "heartbroken",
            "grief", "grieving", "hopeless", "gloomy", "upset", "hurt", "disappointed",
            "feeling down", "felt down", "feel down", "missing", "miss you", "miss home",
            "miss them", "miss him", "miss her",
        ],
        .frustrated: [
            "frustrated", "frustrating", "frustration", "angry", "anger", "annoyed", "annoying",
            "irritated", "irritating", "furious", "fed up", "resent", "unfair", "pissed",
        ],
        .overwhelmed: [
            "overwhelmed", "overwhelming", "too much", "swamped", "drowning", "exhausted",
            "burned out", "burnt out", "burnout", "can't cope", "cannot cope", "overloaded",
            "so much to do", "breaking point",
        ],
    ]

    static let negators: Set<String> = [
        "not", "no", "never", "don't", "dont", "didn't", "didnt", "isn't", "wasn't",
        "aren't", "weren't", "hardly", "without",
    ]
    static let negationWindow = 3

    static let intensifiers: Set<String> = [
        "very", "so", "really", "extremely", "incredibly", "super", "totally",
        "completely", "deeply", "utterly",
    ]
}
