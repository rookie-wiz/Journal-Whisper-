//
//  SafetyGateTests.swift
//  Journal-WhisperTests
//

import Foundation
import Testing
import Synchronization
@testable import Journal_Whisper

struct CrisisCheckTests {

    @Test(arguments: [
        "Some days I just want to die.",
        "I've been thinking about suicide again.",
        "Felt suicidal after the call.",
        "I dont want to live like this anymore",
        "I don’t want to wake up tomorrow.",
        "Everyone would be better off without me.",
        "I cut myself last night.",
        "Thinking about self-harm.",
        "I want to END MY LIFE",
        "He hits me when he's drunk.",
        "I'm afraid to go home tonight.",
    ])
    func flagsCrisisWording(text: String) {
        #expect(SafetyGate.assess(text) == .needsSupport)
    }

    @Test(arguments: [
        "This commute is going to kill me.",
        "I'm dying to see that movie.",
        "We laughed so hard I nearly died.",
        "It finally hits me how much I've grown.",
        "Why did it break? Beats me.",
        "Killed it in my presentation today!",
        "Exams are stressing me out and I feel sad.",
        "",
    ])
    func allowsEverydayWording(text: String) {
        #expect(SafetyGate.assess(text) == .clear)
    }

    @Test func negationStillFlags() {
        // Deliberately conservative: a support card shown by mistake is cheap.
        #expect(SafetyGate.assess("I'm not suicidal, just tired.") == .needsSupport)
    }
}

struct PromptFilterTests {

    @Test func sanitizeStripsFormatting() {
        #expect(SafetyGate.sanitize("1. What made you smile?") == "What made you smile?")
        #expect(SafetyGate.sanitize("  - \"What made   you smile?\"  ") == "What made you smile?")
        #expect(SafetyGate.sanitize("• “Who helped you today?”") == "Who helped you today?")
        #expect(SafetyGate.sanitize("2) What can wait?") == "What can wait?")
    }

    @Test(arguments: [
        "Have you considered talking to your doctor about medication?",
        "Could this be a symptom of depression?",
        "What might a diagnosis change for you?",
        "You should take a break and go for a walk.",
        "Is your prescription helping?",
        "Why?",
        String(repeating: "word ", count: 30) + "?",
        "Do you ever think about suicide?",
    ])
    func rejectsUnsafeOrMalformedPrompts(prompt: String) {
        #expect(!SafetyGate.isAcceptablePrompt(prompt))
    }

    @Test func directivePhrasesInsideQuestionsAreAllowed() {
        // Found by the prompt evaluation.
        #expect(SafetyGate.isAcceptablePrompt("What do you need to feel a little lighter?"))
        #expect(SafetyGate.isAcceptablePrompt("What would you need to let this go?"))
        #expect(!SafetyGate.isAcceptablePrompt("You need to rest more this week."))
        #expect(!SafetyGate.isAcceptablePrompt("Maybe you should talk to her about it?"))
    }

    @Test func acceptsOpenQuestions() {
        #expect(SafetyGate.isAcceptablePrompt("What helped you feel at ease today?"))
        #expect(SafetyGate.isAcceptablePrompt("Describe a moment you felt proud this week."))
    }

    @Test func everyBankPromptPassesTheFilter() {
        let all = PromptBank.general + PromptBank.byMood.values.flatMap { $0 }
        for prompt in all {
            #expect(SafetyGate.isAcceptablePrompt(prompt), "\(prompt)")
        }
    }

    @Test func cleanPromptsKeepsGoodOnesAndTopsUp() {
        let raw = [
            "1. What made today feel different?",
            "You should see a therapist.",
            "what made today feel different?",   // duplicate, different case
        ]
        let cleaned = SafetyGate.cleanPrompts(raw, mood: .calm)
        #expect(cleaned.count == ReflectionDefaults.promptCount)
        #expect(cleaned.first == "What made today feel different?")
        #expect(!cleaned.contains { $0.localizedCaseInsensitiveContains("therapist") })
        #expect(Set(cleaned.map { $0.lowercased() }).count == cleaned.count)
    }

    @Test func cleanPromptsCapsCount() {
        let raw = (1...6).map { "What is good thing number \($0) today?" }
        #expect(SafetyGate.cleanPrompts(raw, mood: nil).count == ReflectionDefaults.promptCount)
    }

    @Test func cleanPromptsFallsBackEntirelyToBank() {
        let cleaned = SafetyGate.cleanPrompts([], mood: .sad)
        let bank = Set(PromptBank.general + PromptBank.byMood[.sad]!)
        #expect(cleaned.count == ReflectionDefaults.promptCount)
        #expect(cleaned.allSatisfy(bank.contains))
    }
}

struct SafeguardedEngineTests {

    @Test func crisisTextNeverReachesTheEngine() async {
        let stub = StubEngine()
        let engine = SafeguardedEngine(stub)
        await #expect(throws: ReflectionError.needsSupport) {
            try await engine.analyzeMood("I want to end it all.")
        }
        await #expect(throws: ReflectionError.needsSupport) {
            try await engine.prompts(for: "I want to end it all.", mood: nil)
        }
        #expect(stub.callCount == 0)
    }

    @Test func passesMoodThrough() async throws {
        let engine = SafeguardedEngine(StubEngine(mood: MoodResult(mood: .calm, intensity: 2, source: .ai)))
        #expect(try await engine.analyzeMood("A quiet day.")?.mood == .calm)
    }

    @Test func filtersEnginePrompts() async throws {
        let stub = StubEngine(prompts: [
            "What surprised you today?",
            "Have you thought about changing your medication?",
        ])
        let prompts = try await SafeguardedEngine(stub).prompts(for: "A day.", mood: .neutral).prompts
        #expect(prompts.count == ReflectionDefaults.promptCount)
        #expect(prompts.first == "What surprised you today?")
        #expect(!prompts.contains { $0.contains("medication") })
    }

    @Test func engineErrorsPropagate() async {
        struct Boom: Error {}
        let engine = SafeguardedEngine(StubEngine(error: Boom()))
        await #expect(throws: Boom.self) { try await engine.prompts(for: "A day.", mood: nil) }
    }
}

/// Returns canned results and counts calls.
final class StubEngine: ReflectionEngine {
    private let mood: MoodResult?
    private let cannedPrompts: [String]
    private let error: (any Error)?
    private let calls = Mutex(0)

    init(mood: MoodResult? = nil, prompts: [String] = [], error: (any Error)? = nil) {
        self.mood = mood
        self.cannedPrompts = prompts
        self.error = error
    }

    var callCount: Int { calls.withLock { $0 } }

    func analyzeMood(_ text: String) async throws -> MoodResult? {
        calls.withLock { $0 += 1 }
        if let error { throw error }
        return mood
    }

    func prompts(for text: String, mood: Mood?) async throws -> PromptSet {
        calls.withLock { $0 += 1 }
        if let error { throw error }
        return PromptSet(prompts: cannedPrompts, source: .ai)
    }
}
