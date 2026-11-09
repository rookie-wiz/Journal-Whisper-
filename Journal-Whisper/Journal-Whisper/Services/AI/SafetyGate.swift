//
//  SafetyGate.swift
//  Journal-Whisper
//
//  Deterministic safety checks that don't depend on the model following its
//  instructions:
//
//  1. Before: `assess(_:)` looks for crisis wording (self-harm, abuse). If found,
//     no AI runs and the app shows supportive resources instead.
//  2. After: `cleanPrompts(_:mood:)` strips formatting from generated prompts,
//     drops any that give medical advice, diagnose, or instruct, and tops the
//     list back up from `PromptBank`.
//
//  The crisis check deliberately has no negation handling and errs towards
//  false positives: showing a gentle support card by mistake costs little;
//  missing a real crisis costs a lot.
//

import Foundation

nonisolated enum SafetyAssessment: Equatable {
    case clear
    case needsSupport
}

nonisolated enum SafetyGate {

    // MARK: - Before: crisis check

    static func assess(_ text: String) -> SafetyAssessment {
        let tokens = normalizedTokens(text)
        guard !tokens.isEmpty else { return .clear }
        let found = crisisPhrases.contains { phrase in containsPhrase(phrase, in: tokens) }
            || tokens.contains { token in crisisPrefixes.contains { token.hasPrefix($0) } }
        return found ? .needsSupport : .clear
    }

    /// Multi-word phrases, written without apostrophes ("dont", "im").
    /// Figurative uses like "this will kill me" or "dying to see it" are intentionally absent.
    private static let crisisPhrases: [[String]] = [
        "kill myself", "killing myself", "end my life", "ending my life", "take my own life",
        "want to die", "wanna die", "wish i was dead", "wish i were dead", "better off dead",
        "better off without me", "dont want to live", "dont want to be alive",
        "dont want to be here anymore", "dont want to wake up", "no reason to live",
        "nothing to live for", "end it all", "hurt myself", "hurting myself", "harm myself",
        "harming myself", "self harm", "cut myself", "cutting myself", "overdose",
        // Abuse. Bare "hits me" / "beats me" are common idioms, so a person is named.
        "he hits me", "she hits me", "they hit me", "he hit me", "she hit me",
        "he beats me", "she beats me", "abusing me", "abused me", "afraid to go home",
        "not safe at home",
    ].map { $0.split(separator: " ").map(String.init) }

    /// Word stems that are a crisis signal on their own (suicide, suicidal, …).
    private static let crisisPrefixes = ["suicid"]

    // MARK: - After: prompt filtering

    /// Cleans generated prompts, drops unsafe or malformed ones, removes
    /// duplicates, and fills any gaps from the prompt bank.
    static func cleanPrompts(
        _ prompts: [String],
        mood: Mood?,
        count: Int = ReflectionDefaults.promptCount
    ) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        func add(_ prompt: String) {
            guard result.count < count, seen.insert(prompt.lowercased()).inserted else { return }
            result.append(prompt)
        }
        prompts.map(sanitize).filter(isAcceptablePrompt).forEach(add)
        if result.count < count {
            PromptBank.pick(for: mood, count: count + result.count).forEach(add)
        }
        if result.count < count {
            // Still short only if the bank overlapped heavily; general prompts always suffice.
            PromptBank.general.forEach(add)
        }
        return result
    }

    /// Removes list markers, wrapping quotes and extra whitespace a model may add.
    static func sanitize(_ prompt: String) -> String {
        var text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // "1. ", "2) ", "- ", "• ", "* "
        if let range = text.range(of: #"^(\d+[.)]|[-•*])\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        let quotes = CharacterSet(charactersIn: "\"'“”‘’")
        text = text.trimmingCharacters(in: quotes.union(.whitespacesAndNewlines))
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func isAcceptablePrompt(_ prompt: String) -> Bool {
        let words = prompt.split(separator: " ")
        guard (3...25).contains(words.count), prompt.count <= 200 else { return false }
        // A prompt should never itself contain crisis wording.
        return !hasClinicalOrDirectiveLanguage(prompt) && assess(prompt) == .clear
    }

    /// Medical, diagnostic or clinical vocabulary, or telling the reader what to do.
    /// Shared by prompts, weekly summaries and per-entry notes.
    static func hasClinicalOrDirectiveLanguage(_ text: String) -> Bool {
        let tokens = normalizedTokens(text)
        if tokens.contains(where: { token in
            blockedWords.contains(token) || blockedPrefixes.contains { token.hasPrefix($0) }
        }) { return true }
        return blockedPhrases.contains { isDirective($0, in: tokens) }
    }

    // MARK: - Plain-text output (weekly summaries)

    /// With permissive guardrails, plain-text requests don't throw on sensitive
    /// input; the model may answer with a refusal message instead. Catch those.
    static func looksLikeRefusal(_ text: String) -> Bool {
        let start = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
        return refusalOpenings.contains { start.hasPrefix($0) }
            || start.contains("as an ai")
            || start.contains("i can't help with")
            || start.contains("i cannot help with")
    }

    private static let refusalOpenings = [
        "i'm sorry", "i am sorry", "sorry,", "i can't", "i cannot", "i'm unable", "i am unable",
        "i'm not able", "i am not able", "i won't", "i will not", "unfortunately, i",
    ]

    /// Strips formatting a model may add around prose: labels, bold, wrapping quotes, extra spaces.
    static func sanitizeProse(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = result.range(of: #"^(summary|reflection|note)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            result.removeSubrange(range)
        }
        result = result.replacingOccurrences(of: "**", with: "")
        let quotes = CharacterSet(charactersIn: "\"“”")
        result = result.trimmingCharacters(in: quotes.union(.whitespacesAndNewlines))
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The on-device model sometimes answers entirely in lower case. When there's
    /// no capital letter at all, restore sentence starts, "I", and day and month
    /// names. Text that already has capitals is left alone, so names aren't touched.
    static func restoreCapitalisation(_ text: String) -> String {
        guard !text.isEmpty, !text.contains(where: \.isUppercase) else { return text }
        let properNouns: Set<String> = [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "january", "february", "march", "april", "may", "june", "july", "august",
            "september", "october", "november", "december", "i", "i'm", "i've", "i'd", "i'll",
        ]
        var result = ""
        var startOfSentence = true
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            var word = String(word)
            let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if startOfSentence || properNouns.contains(bare),
               let index = word.firstIndex(where: \.isLetter) {
                word.replaceSubrange(index...index, with: word[index].uppercased())
            }
            result += result.isEmpty ? word : " " + word
            if let last = word.last { startOfSentence = ".!?".contains(last) } else { startOfSentence = false }
        }
        return result
    }

    /// A weekly summary shown to the user.
    static func isAcceptableSummary(_ text: String) -> Bool {
        guard (40...800).contains(text.count), !looksLikeRefusal(text) else { return false }
        return !hasClinicalOrDirectiveLanguage(text) && assess(text) == .clear
    }

    /// A one-line note on an entry (model input only, never shown directly).
    static func isAcceptableGist(_ text: String) -> Bool {
        let words = text.split(separator: " ").count
        return (3...40).contains(words) && !looksLikeRefusal(text) && assess(text) == .clear
    }

    /// Medical, diagnostic and clinical vocabulary. Prompts reflect; they don't treat or label.
    private static let blockedWords: Set<String> = [
        "disorder", "disorders", "medication", "medications", "medicine", "meds", "dose",
        "dosage", "pill", "pills", "symptom", "symptoms", "treatment", "treat", "cure",
        "clinical", "depression", "depressed", "adhd", "ptsd", "ocd", "bipolar",
        "doctor", "therapist", "therapy", "psychiatrist", "condition", "illness",
    ]
    private static let blockedPrefixes = ["diagnos", "prescri", "antidepress"]

    /// Directive phrasing: prompts ask, they don't tell.
    private static let blockedPhrases: [[String]] = [
        "you should", "you must", "you need to", "you have to", "make sure you",
    ].map { $0.split(separator: " ").map(String.init) }

    // MARK: - Helpers

    /// Lowercased words with apostrophes removed, so "don't" and "dont" match the same phrase.
    private static func normalizedTokens(_ text: String) -> [String] {
        HeuristicEngine.tokenize(text).map { $0.replacingOccurrences(of: "'", with: "") }
    }

    /// Words that turn a following "you need to" / "you should" into a question
    /// ("What do you need to feel lighter?") rather than an instruction.
    private static let questionLeads: Set<String> = ["do", "did", "does", "would", "could", "might", "will"]

    /// True if the phrase appears as an instruction, not as part of a question.
    /// Found by the prompt evaluation: v1 of this check rejected
    /// "What do you need to feel a little lighter?".
    private static func isDirective(_ phrase: [String], in tokens: [String]) -> Bool {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return false }
        return (0...(tokens.count - phrase.count)).contains { start in
            phrase.indices.allSatisfy { tokens[start + $0] == phrase[$0] }
                && !(start > 0 && questionLeads.contains(tokens[start - 1]))
        }
    }

    private static func containsPhrase(_ phrase: [String], in tokens: [String]) -> Bool {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return false }
        return (0...(tokens.count - phrase.count)).contains { start in
            phrase.indices.allSatisfy { tokens[start + $0] == phrase[$0] }
        }
    }
}

/// Wraps any engine so the safety checks always run, whichever engine is in use.
nonisolated struct SafeguardedEngine: ReflectionEngine {
    let base: any ReflectionEngine

    init(_ base: any ReflectionEngine) {
        self.base = base
    }

    func analyzeMood(_ text: String) async throws -> MoodResult? {
        // Don't reduce a crisis entry to a mood tag, and don't send it to the model.
        guard SafetyGate.assess(text) == .clear else { throw ReflectionError.needsSupport }
        return try await base.analyzeMood(text)
    }

    func prewarm() { base.prewarm() }

    func prompts(for text: String, mood: Mood?) async throws -> PromptSet {
        guard SafetyGate.assess(text) == .clear else { throw ReflectionError.needsSupport }
        let raw = try await base.prompts(for: text, mood: mood)
        return PromptSet(
            prompts: SafetyGate.cleanPrompts(raw.prompts, mood: mood),
            source: raw.source,
            fallbackReason: raw.fallbackReason
        )
    }
}
