//
//  MockReflectionEngine.swift
//  Journal-Whisper
//
//  Debug-only stand-in for the on-device model, so UI tests and previews behave
//  the same on every machine, with or without Apple Intelligence.
//
//  Launch arguments (with -uiTesting):
//    -mockAI          use this engine as the "model": instant, fixed answers
//    -mockAIFailure   the "model" always fails, to exercise the offline fallback
//

#if DEBUG
import Foundation

nonisolated struct MockReflectionEngine: ReflectionEngine {
    static let mood = MoodResult(mood: .calm, intensity: 3, source: .ai)
    static let prompts = [
        "What felt most important about today?",
        "Where did you notice a change in how you felt?",
        "What would you like to carry into tomorrow?",
    ]

    var fails = false

    func analyzeMood(_ text: String) async throws -> MoodResult? {
        if fails { throw ReflectionError.generationFailed(.guardrail) }
        return Self.mood
    }

    func prompts(for text: String, mood: Mood?) async throws -> PromptSet {
        if fails { throw ReflectionError.generationFailed(.guardrail) }
        return PromptSet(prompts: Self.prompts, source: .ai)
    }
}

/// Debug stand-in for the model summary: instant and fixed. Fails on -mockAIFailure.
nonisolated struct MockSummaryEngine: SummaryEngine {
    static let text = "This week you made time to write, and calm moments sat alongside some worry."
    var fails = false

    func summarize(_ week: WeekSnapshot) async throws -> SummaryDraft {
        if fails { throw ReflectionError.generationFailed(.refusal) }
        return SummaryDraft(text: Self.text, source: .ai,
                            closingQuestion: week.needsSupport ? nil : MockReflectionEngine.prompts[0])
    }
}

extension SummaryEngineFactory {
    /// The summary engine for this launch: the mock for UI tests, otherwise the real one.
    nonisolated static func makeForLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> any SummaryEngine {
        let mockFailure = arguments.contains("-mockAIFailure")
        guard arguments.contains("-mockAI") || mockFailure else { return makeDefault() }
        // Same fallback wrapper as production.
        return FallbackSummaryEngine(primary: MockSummaryEngine(fails: mockFailure))
    }
}

extension ReflectionEngineFactory {
    /// The engine for this launch: the mock when UI tests ask for it, otherwise the real stack.
    nonisolated static func makeForLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> any ReflectionEngine {
        let mockFailure = arguments.contains("-mockAIFailure")
        guard arguments.contains("-mockAI") || mockFailure else { return makeDefault() }
        // Same wrappers as production, so safety and fallback behave identically.
        return SafeguardedEngine(FallbackEngine(
            primary: MockReflectionEngine(fails: mockFailure),
            fallback: HeuristicEngine()
        ))
    }
}
#endif
