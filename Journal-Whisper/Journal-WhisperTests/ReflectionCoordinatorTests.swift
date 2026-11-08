//
//  ReflectionCoordinatorTests.swift
//  Journal-WhisperTests
//

import Foundation
import Testing
import SwiftData
import FoundationModels
import Synchronization
@testable import Journal_Whisper

/// About 30 words with a clear anxious signal.
private let anxiousText = """
    Exams start tomorrow and I'm really nervous. I keep going over the same notes \
    and worrying that I've missed something important. I couldn't eat much at dinner.
    """

@MainActor
private func makeEntry(text: String = anxiousText, title: String = "") throws -> (JournalEntry, ModelContainer) {
    let container = try ModelContainer(
        for: JournalEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let entry = JournalEntry(title: title, text: text)
    container.mainContext.insert(entry)
    return (entry, container)
}

/// Polls until the condition holds or the timeout passes.
@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private let calmResult = MoodResult(mood: .calm, intensity: 2, source: .ai)

@MainActor
struct ReflectionCoordinatorMoodTests {

    @Test func appliesSuggestedMood() async throws {
        let (entry, _container) = try makeEntry()
        let coordinator = ReflectionCoordinator(engine: StubEngine(mood: calmResult))
        await coordinator.analyzeMoodIfNeeded(entry)
        #expect(entry.mood == .calm)
        #expect(entry.moodSource == .ai)
        #expect(entry.moodAnalyzedAt != nil)
        #expect(!coordinator.isAnalyzingMood)
        _ = _container
    }

    @Test func skipsShortEntries() async throws {
        let (entry, _container) = try makeEntry(text: "Bit nervous today.")
        let stub = StubEngine(mood: calmResult)
        await ReflectionCoordinator(engine: stub).analyzeMoodIfNeeded(entry)
        #expect(stub.callCount == 0)
        #expect(entry.mood == nil)
        _ = _container
    }

    @Test func titleCountsTowardsWordMinimum() {
        let entry = JournalEntry(title: "One two three", text: "four five")
        #expect(entry.wordCount == 5)
        #expect(entry.reflectionText == "One two three\n\nfour five")
    }

    @Test func neverRunsWhenUserChoseMood() async throws {
        let (entry, _container) = try makeEntry()
        entry.setUserMood(.joyful)
        let stub = StubEngine(mood: calmResult)
        await ReflectionCoordinator(engine: stub).analyzeMoodIfNeeded(entry)
        #expect(stub.callCount == 0)
        #expect(entry.mood == .joyful)
        _ = _container
    }

    @Test func skipsUnchangedTextAndRerunsAfterEdit() async throws {
        let (entry, _container) = try makeEntry()
        let stub = StubEngine(mood: calmResult)
        let coordinator = ReflectionCoordinator(engine: stub)

        await coordinator.analyzeMoodIfNeeded(entry)
        await coordinator.analyzeMoodIfNeeded(entry)
        #expect(stub.callCount == 1)

        entry.text += " Later I felt better."
        entry.updatedAt = .now.addingTimeInterval(1)
        await coordinator.analyzeMoodIfNeeded(entry)
        #expect(stub.callCount == 2)
        _ = _container
    }

    @Test func failedAnalysisDoesNotMarkAsAnalyzed() async throws {
        let (entry, _container) = try makeEntry()
        let stub = StubEngine(error: ReflectionError.generationFailed(.other))
        await ReflectionCoordinator(engine: stub).analyzeMoodIfNeeded(entry)
        #expect(entry.moodAnalyzedAt == nil)
        #expect(entry.needsMoodAnalysis)
        _ = _container
    }

    @Test func noSignalStillMarksAsAnalyzed() async throws {
        let (entry, _container) = try makeEntry()
        await ReflectionCoordinator(engine: StubEngine(mood: nil)).analyzeMoodIfNeeded(entry)
        #expect(entry.mood == nil)
        #expect(!entry.needsMoodAnalysis)
        _ = _container
    }

    @Test func debouncedChangeRunsAnalysis() async throws {
        let (entry, _container) = try makeEntry()
        let coordinator = ReflectionCoordinator(engine: StubEngine(mood: calmResult), debounce: .zero)
        coordinator.entryDidChange(entry)
        await waitUntil { entry.mood != nil }
        #expect(entry.mood == .calm)
        _ = _container
    }

    @Test func rapidChangesAnalyseOnce() async throws {
        let (entry, _container) = try makeEntry()
        let stub = StubEngine(mood: calmResult)
        let coordinator = ReflectionCoordinator(engine: stub, debounce: .milliseconds(100))
        for _ in 0..<5 { coordinator.entryDidChange(entry) }
        await waitUntil { entry.mood != nil }
        try await Task.sleep(for: .milliseconds(200))
        #expect(stub.callCount == 1)
        _ = _container
    }

    @Test func closingAnalysesImmediately() async throws {
        let (entry, _container) = try makeEntry()
        let coordinator = ReflectionCoordinator(engine: StubEngine(mood: calmResult), debounce: .seconds(60))
        coordinator.entryDidChange(entry)
        await coordinator.entryWillClose(entry).value
        #expect(entry.mood == .calm)
        _ = _container
    }

    @Test func deletedEntryIsLeftAlone() async throws {
        let (entry, container) = try makeEntry()
        container.mainContext.delete(entry)
        try container.mainContext.save()
        await ReflectionCoordinator(engine: StubEngine(mood: calmResult)).analyzeMoodIfNeeded(entry)
        #expect(entry.moodRaw == nil)
    }
}

@MainActor
struct ReflectionCoordinatorPromptTests {

    @Test func requestShowsPrompts() async throws {
        let (entry, _container) = try makeEntry()
        let prompts = ["What would help?", "Who could you talk to?", "What can wait?"]
        let coordinator = ReflectionCoordinator(engine: StubEngine(prompts: prompts))
        coordinator.requestPrompts(for: entry)
        #expect(coordinator.promptState == .loading)
        await waitUntil { coordinator.promptState != .loading }
        #expect(coordinator.promptState == .ready(prompts))
        _ = _container
    }

    @Test func engineFailureFallsBackToBank() async throws {
        let (entry, _container) = try makeEntry()
        let coordinator = ReflectionCoordinator(engine: StubEngine(error: ReflectionError.generationFailed(.guardrail)))
        coordinator.requestPrompts(for: entry)
        await waitUntil { coordinator.promptState != .loading }
        guard case .ready(let prompts) = coordinator.promptState else {
            Issue.record("Expected prompts, got \(coordinator.promptState)")
            return
        }
        #expect(prompts.count == ReflectionDefaults.promptCount)
        _ = _container
    }

    @Test func usingAPromptAppendsIt() throws {
        let (entry, _container) = try makeEntry(text: "Long day.")
        let coordinator = ReflectionCoordinator(engine: StubEngine())
        coordinator.use("What made it long?", in: entry)
        #expect(entry.text == "Long day.\n\nWhat made it long?\n")
        #expect(coordinator.promptState == .hidden)

        let blank = JournalEntry()
        coordinator.use("Where are you right now?", in: blank)
        #expect(blank.text == "Where are you right now?\n")
        _ = _container
    }

    @Test func dismissHidesPrompts() async throws {
        let (entry, _container) = try makeEntry()
        let coordinator = ReflectionCoordinator(engine: StubEngine(prompts: ["What helped today?"]))
        coordinator.requestPrompts(for: entry)
        await waitUntil { coordinator.promptState != .loading }
        coordinator.dismissPrompts()
        #expect(coordinator.promptState == .hidden)
        _ = _container
    }
}

@MainActor
struct ReflectionCoordinatorSafetyTests {

    @Test func crisisWordingShowsSupportWithoutCallingEngine() async throws {
        let (entry, _container) = try makeEntry(text: "I want to die.")
        let stub = StubEngine(mood: calmResult)
        let coordinator = ReflectionCoordinator(engine: stub, debounce: .zero)
        coordinator.entryDidChange(entry)
        #expect(coordinator.promptState == .support)
        try await Task.sleep(for: .milliseconds(50))
        #expect(stub.callCount == 0)
        _ = _container
    }

    @Test func supportClearsWhenWordingIsRemoved() throws {
        let (entry, _container) = try makeEntry(text: "I want to die.")
        let coordinator = ReflectionCoordinator(engine: StubEngine())
        coordinator.entryDidAppear(entry)
        #expect(coordinator.promptState == .support)
        entry.text = "Feeling a bit better after talking to my sister."
        coordinator.entryDidChange(entry)
        #expect(coordinator.promptState == .hidden)
        _ = _container
    }

    @Test func supportSurvivesDismiss() throws {
        let (entry, _container) = try makeEntry(text: "Thinking about suicide.")
        let coordinator = ReflectionCoordinator(engine: StubEngine())
        coordinator.entryDidAppear(entry)
        coordinator.dismissPrompts()
        #expect(coordinator.promptState == .support)
        _ = _container
    }

    @Test func engineSupportErrorShowsSupport() async throws {
        let (entry, _container) = try makeEntry()
        let coordinator = ReflectionCoordinator(engine: StubEngine(error: ReflectionError.needsSupport))
        coordinator.requestPrompts(for: entry)
        await waitUntil { coordinator.promptState != .loading }
        #expect(coordinator.promptState == .support)
        _ = _container
    }
}

struct FallbackEngineTests {

    @Test func usesPrimaryWhenItWorks() async throws {
        let primary = StubEngine(mood: calmResult), fallback = StubEngine()
        let result = try await FallbackEngine(primary: primary, fallback: fallback).analyzeMood("x")
        #expect(result == calmResult)
        #expect(fallback.callCount == 0)
    }

    @Test(arguments: [GenerationFailure.unavailable, .guardrail, .refusal, .contextTooLong, .other])
    func fallsBackOnFailure(failure: GenerationFailure) async throws {
        let heuristic = MoodResult(mood: .sad, intensity: 3, source: .heuristic)
        let engine = FallbackEngine(
            primary: StubEngine(error: ReflectionError.generationFailed(failure)),
            fallback: StubEngine(mood: heuristic, prompts: ["What do you need?"])
        )
        #expect(try await engine.analyzeMood("x") == heuristic)
        #expect(try await engine.prompts(for: "x", mood: nil) == ["What do you need?"])
    }

    @Test func passesSupportAndCancellationThrough() async {
        let fallback = StubEngine()
        let support = FallbackEngine(primary: StubEngine(error: ReflectionError.needsSupport), fallback: fallback)
        await #expect(throws: ReflectionError.needsSupport) { try await support.analyzeMood("x") }
        let cancelled = FallbackEngine(primary: StubEngine(error: CancellationError()), fallback: fallback)
        await #expect(throws: CancellationError.self) { try await cancelled.prompts(for: "x", mood: nil) }
        #expect(fallback.callCount == 0)
    }

    @Test func offlineStackWorksEndToEnd() async throws {
        let engine = ReflectionEngineFactory.makeOffline()
        #expect(try await engine.analyzeMood(anxiousText)?.mood == .anxious)
        #expect(try await engine.prompts(for: anxiousText, mood: .anxious).count == ReflectionDefaults.promptCount)
        await #expect(throws: ReflectionError.needsSupport) { try await engine.analyzeMood("I want to die") }
    }
}

struct FoundationModelsMappingTests {

    @Test func generatedMoodsMatchMoods() {
        #expect(GeneratedMood.allCases.map(\.rawValue) == Mood.allCases.map(\.rawValue))
        for generated in GeneratedMood.allCases {
            #expect(generated.mood.rawValue == generated.rawValue)
        }
    }

    @Test func mapsFrameworkErrors() {
        typealias E = LanguageModelError
        #expect(FoundationModelsEngine.failure(for: E.guardrailViolation(.init(debugDescription: ""))) == .guardrail)
        #expect(FoundationModelsEngine.failure(for: E.refusal(.init(explanation: "", debugDescription: ""))) == .refusal)
        #expect(FoundationModelsEngine.failure(
            for: E.contextSizeExceeded(.init(contextSize: 1, tokenCount: 2, debugDescription: ""))) == .contextTooLong)
        #expect(FoundationModelsEngine.failure(
            for: SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: ""))) == .unavailable)
        struct Other: Error {}
        #expect(FoundationModelsEngine.failure(for: Other()) == .other)
    }
}

struct ReflectionInstructionsTests {

    @Test func shortTextIsSentWhole() {
        #expect(ReflectionInstructions.excerpt(of: "Hello there") == "Hello there")
    }

    @Test func longTextKeepsTheEndAtAWordBoundary() {
        let text = "start " + String(repeating: "word ", count: 3_000) + "the end"
        let excerpt = ReflectionInstructions.excerpt(of: text)
        #expect(excerpt.count <= ReflectionInstructions.maxExcerptLength + 1)
        #expect(excerpt.hasPrefix("…word"))
        #expect(excerpt.hasSuffix("the end"))
    }

    @Test func blankEntryAsksForStarterQuestions() {
        let request = ReflectionInstructions.promptsRequest(for: "  ", mood: nil, count: 3)
        #expect(request.contains("hasn't written anything"))
        #expect(!request.contains("<entry>"))
    }

    @Test func requestIncludesMoodAndDelimitedEntry() {
        let request = ReflectionInstructions.promptsRequest(for: "Rainy walk.", mood: .calm, count: 3)
        #expect(request.contains("calm"))
        #expect(request.contains("<entry>\nRainy walk.\n</entry>"))
    }

    @Test func instructionsForbidMedicalAdvice() {
        #expect(ReflectionInstructions.prompts.contains("Never give medical"))
        #expect(ReflectionInstructions.prompts.contains("Never diagnose"))
    }
}

struct ModelCallTimeoutTests {

    @Test func fastCallReturns() async throws {
        let value = try await FoundationModelsEngine.run(timeout: .seconds(1)) { 42 }
        #expect(value == 42)
    }

    @Test func slowCallTimesOut() async {
        let start = ContinuousClock.now
        await #expect(throws: ReflectionError.generationFailed(.timeout)) {
            try await FoundationModelsEngine.run(timeout: .milliseconds(50)) {
                try await Task.sleep(for: .seconds(10))
                return 0
            }
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func frameworkErrorsAreMapped() async {
        await #expect(throws: ReflectionError.generationFailed(.guardrail)) {
            try await FoundationModelsEngine.run(timeout: .seconds(1)) { () -> Int in
                throw LanguageModelError.guardrailViolation(.init(debugDescription: ""))
            }
        }
    }
}

struct PrewarmTests {
    final class PrewarmSpy: ReflectionEngine {
        let count = Mutex(0)
        func analyzeMood(_ text: String) async throws -> MoodResult? { nil }
        func prompts(for text: String, mood: Mood?) async throws -> [String] { [] }
        func prewarm() { count.withLock { $0 += 1 } }
    }

    @Test func wrappersForwardPrewarmToPrimary() {
        let primary = PrewarmSpy(), fallback = PrewarmSpy()
        SafeguardedEngine(FallbackEngine(primary: primary, fallback: fallback)).prewarm()
        #expect(primary.count.withLock { $0 } == 1)
        #expect(fallback.count.withLock { $0 } == 0)
    }

    @MainActor @Test func openingEditorPrewarms() {
        let spy = PrewarmSpy()
        ReflectionCoordinator(engine: spy).entryDidAppear(JournalEntry(text: "Hi"))
        #expect(spy.count.withLock { $0 } == 1)
    }
}

struct LaunchEngineTests {

    @Test func mockAIUsesMockPrompts() async throws {
        let engine = ReflectionEngineFactory.makeForLaunch(arguments: ["-uiTesting", "-mockAI"])
        #expect(try await engine.prompts(for: "A day.", mood: nil) == MockReflectionEngine.prompts)
        #expect(try await engine.analyzeMood("A day.") == MockReflectionEngine.mood)
    }

    @Test func mockFailureFallsBackToOffline() async throws {
        let engine = ReflectionEngineFactory.makeForLaunch(arguments: ["-uiTesting", "-mockAIFailure"])
        let prompts = try await engine.prompts(for: "A day.", mood: nil)
        #expect(prompts.count == ReflectionDefaults.promptCount)
        #expect(Set(prompts).isDisjoint(with: MockReflectionEngine.prompts))
    }

    @Test func mockStillGoesThroughSafety() async {
        let engine = ReflectionEngineFactory.makeForLaunch(arguments: ["-mockAI"])
        await #expect(throws: ReflectionError.needsSupport) { try await engine.prompts(for: "I want to die", mood: nil) }
    }

    @Test func noFlagsUsesRealStack() {
        let engine = ReflectionEngineFactory.makeForLaunch(arguments: [])
        #expect(engine is SafeguardedEngine)
        #expect((engine as? SafeguardedEngine)?.base is FallbackEngine)
    }
}
