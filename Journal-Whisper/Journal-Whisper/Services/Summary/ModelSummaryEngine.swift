//
//  ModelSummaryEngine.swift
//  Journal-Whisper
//
//  Weekly summaries from the on-device model, degrading in steps instead of
//  all-or-nothing:
//
//  1. Whole week in one request, if it fits the context window.
//  2. If that's too long, declined or unsafe: a one-line note per entry
//     (cached on the entry), skipping entries the model declines, then a
//     summary of the notes. One hard entry costs only its own note.
//  3. If fewer than two notes survive, or the model is unavailable or slow:
//     throw, and FallbackSummaryEngine uses the offline template.
//
//  Entries with crisis wording are never sent to the model. Every summary
//  is checked for refusal text and clinical or directive language before use.
//

import Foundation
import os

nonisolated struct ModelSummaryEngine: SummaryEngine {
    let generator: any SummaryTextGenerator
    /// Writes the closing question (with its own safety and fallback).
    let questionEngine: any ReflectionEngine

    /// Weeks with fewer usable entries get the template: too little to reflect on.
    static let minimumEntries = 2
    static let summaryTimeout: Duration = .seconds(25)
    static let gistTimeout: Duration = .seconds(10)
    static let summaryTokens = 220
    static let gistTokens = 60

    private static let logger = Logger(subsystem: "com.shubh.Journal-Whisper", category: "Summary")

    func summarize(_ week: WeekSnapshot) async throws -> SummaryDraft {
        // Crisis entries never go to the model (the card shows support instead).
        let usable = week.entries.filter { SafetyGate.assess($0.text) == .clear }
        guard usable.count >= Self.minimumEntries else {
            return TemplateSummaryEngine.draft(for: week)
        }
        guard generator.isAvailable else { throw ReflectionError.generationFailed(.unavailable) }

        // Step 1: the whole week at once.
        let firstFailure: GenerationFailure
        let wholeWeek = SummaryInstructions.weekRequest(entries: usable, statistics: week.statistics)
        if await generator.fits(instructions: SummaryInstructions.summary, prompt: wholeWeek, reserve: Self.summaryTokens) {
            do {
                let text = try await generateSummary(prompt: wholeWeek)
                return await draft(text, for: week, gists: [:])
            } catch ReflectionError.generationFailed(let failure) where Self.notesMightHelp(failure) {
                firstFailure = failure
            }
        } else {
            firstFailure = .contextTooLong
        }
        Self.logger.notice("Summary step 1 failed (\(firstFailure.rawValue, privacy: .public)); trying per-entry notes")

        // Step 2: a note per entry, then a summary of the notes.
        var notes: [(entry: EntrySnapshot, gist: String)] = []
        var newGists: [GistKey: String] = [:]
        for entry in usable {
            if let cached = entry.gist {
                notes.append((entry, cached))
                continue
            }
            do {
                let raw = try await generator.generate(
                    instructions: SummaryInstructions.gist,
                    prompt: SummaryInstructions.gistRequest(for: entry),
                    maxTokens: Self.gistTokens,
                    timeout: Self.gistTimeout
                )
                let gist = SafetyGate.sanitizeProse(raw)
                guard SafetyGate.isAcceptableGist(gist) else { continue }   // declined: skip this entry
                notes.append((entry, gist))
                newGists[GistKey(entry)] = gist
            } catch ReflectionError.generationFailed(let failure) where !Self.notesMightHelp(failure) {
                break   // Unavailable or slow: more requests won't help.
            } catch ReflectionError.generationFailed {
                continue   // This entry was declined; the others may be fine.
            }
        }
        guard notes.count >= Self.minimumEntries else {
            throw ReflectionError.generationFailed(firstFailure)
        }
        do {
            let text = try await generateSummary(prompt: SummaryInstructions.gistsRequest(notes, statistics: week.statistics))
            return await draft(text, for: week, gists: newGists)
        } catch ReflectionError.generationFailed {
            throw ReflectionError.generationFailed(firstFailure)
        }
    }

    // MARK: - Pieces

    /// Generates and checks a summary. A refusal or unsafe text counts as a decline.
    private func generateSummary(prompt: String) async throws -> String {
        let raw = try await generator.generate(
            instructions: SummaryInstructions.summary,
            prompt: prompt,
            maxTokens: Self.summaryTokens,
            timeout: Self.summaryTimeout
        )
        let text = SafetyGate.restoreCapitalisation(SafetyGate.sanitizeProse(raw))
        if SafetyGate.looksLikeRefusal(text) { throw ReflectionError.generationFailed(.refusal) }
        guard SafetyGate.isAcceptableSummary(text) else { throw ReflectionError.generationFailed(.guardrail) }
        return text
    }

    private func draft(_ text: String, for week: WeekSnapshot, gists: [GistKey: String]) async -> SummaryDraft {
        SummaryDraft(text: text, source: .ai, closingQuestion: await closingQuestion(for: text, week: week), gists: gists)
    }

    private func closingQuestion(for summary: String, week: WeekSnapshot) async -> String? {
        guard !week.needsSupport else { return nil }
        let question = try? await questionEngine.prompts(for: summary, mood: week.statistics.dominantMood).prompts.first
        return question ?? TemplateSummaryEngine.closingQuestion(for: week)
    }

    /// Declines and length problems may succeed one entry at a time; being
    /// unavailable, slow, busy or in an unsupported language won't.
    static func notesMightHelp(_ failure: GenerationFailure) -> Bool {
        switch failure {
        case .guardrail, .refusal, .contextTooLong, .other: true
        case .unavailable, .busy, .timeout, .unsupportedLanguage: false
        }
    }
}

/// Uses the offline template when the model engine gives up, recording why.
nonisolated struct FallbackSummaryEngine: SummaryEngine {
    let primary: any SummaryEngine
    let fallback: any SummaryEngine = TemplateSummaryEngine()

    func summarize(_ week: WeekSnapshot) async throws -> SummaryDraft {
        do {
            return try await primary.summarize(week)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            var draft = try await fallback.summarize(week)
            draft.fallbackReason = FallbackEngine.failure(of: error)
            return draft
        }
    }
}

nonisolated enum SummaryEngineFactory {
    static func makeDefault(questions: any ReflectionEngine = ReflectionEngineFactory.makeDefault()) -> any SummaryEngine {
        FallbackSummaryEngine(primary: ModelSummaryEngine(generator: FoundationModelsTextGenerator(), questionEngine: questions))
    }
}
