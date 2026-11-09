//
//  GracefulFallbackTests.swift
//  Journal-WhisperTests
//
//  Week 3 "handle guardrail errors gracefully": provenance, calm notes, not
//  re-asking the model after a decline, and serialised model requests.
//

import Foundation
import Testing
import SwiftData
import Synchronization
@testable import Journal_Whisper

// MARK: - Failure kinds and notes

struct FallbackNoteTests {

    @Test func deterministicFailures() {
        let repeating: Set<GenerationFailure> = [.guardrail, .refusal, .contextTooLong, .unsupportedLanguage]
        for failure in [GenerationFailure.unavailable, .guardrail, .refusal, .contextTooLong,
                        .unsupportedLanguage, .busy, .timeout, .other] {
            #expect(failure.isDeterministic == repeating.contains(failure), "\(failure)")
        }
    }

    private func note(_ source: Provenance, _ reason: GenerationFailure?,
                      _ availability: ReflectionAvailability = .available) -> String? {
        ReflectionPromptCard.note(for: PromptSet(prompts: [], source: source, fallbackReason: reason),
                                  availability: availability)
    }

    @Test func personalisedPromptsHaveNoNote() {
        #expect(note(.ai, nil) == nil)
    }

    @Test func declinedEntryGetsAGentleNote() {
        let text = note(.offline, .guardrail)
        #expect(text?.contains("aren't available for this entry") == true)
        #expect(note(.offline, .refusal) == text)
        // No alarming words.
        for word in ["error", "failed", "blocked", "unsafe", "guardrail", "refused"] {
            #expect(text?.localizedCaseInsensitiveContains(word) == false, "\(word)")
        }
    }

    @Test func transientFailuresSayForNow() {
        for reason in [GenerationFailure.timeout, .busy, .other, .contextTooLong, .unavailable] {
            #expect(note(.offline, reason) == "Showing general prompts for now.", "\(reason)")
        }
    }

    @Test func languageNote() {
        #expect(note(.offline, .unsupportedLanguage)?.contains("language") == true)
    }

    @Test func actionableAvailabilityWins() {
        #expect(note(.offline, .guardrail, .appleIntelligenceOff)?.contains("Apple Intelligence") == true)
    }

    @Test func offlineByDesignNeedsNoNote() {
        #expect(note(.offline, nil) == nil)
        #expect(note(.offline, nil, .deviceNotEligible) == nil)
    }
}

// MARK: - Not re-asking after a decline

@MainActor
struct DeclineMemoryTests {

    private func makeEntry(_ text: String) throws -> (JournalEntry, ModelContainer) {
        let container = try ModelContainer(for: JournalEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let entry = JournalEntry(text: text)
        container.mainContext.insert(entry)
        return (entry, container)
    }

    private func waitForPrompts(_ coordinator: ReflectionCoordinator) async -> PromptSet? {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if case .ready(let set) = coordinator.promptState { return set }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    /// Model stack that always declines, as FallbackEngine would report it.
    private func decliningStack(_ failure: GenerationFailure) -> (model: StubEngine, stack: FallbackEngine) {
        let model = StubEngine(error: ReflectionError.generationFailed(failure))
        return (model, FallbackEngine(primary: model, fallback: HeuristicEngine()))
    }

    @Test func declinedTextIsNotSentAgain() async throws {
        let (entry, container) = try makeEntry("A hard day I don't want to talk about.")
        let (model, stack) = decliningStack(.guardrail)
        let offline = StubEngine(prompts: ["What do you need right now?"])
        let coordinator = ReflectionCoordinator(engine: stack, offlineEngine: offline)

        coordinator.requestPrompts(for: entry)
        let first = await waitForPrompts(coordinator)
        #expect(first?.fallbackReason == .guardrail)
        #expect(model.callCount == 1)

        // Refresh with the same text: straight to offline, reason kept for the note.
        coordinator.requestPrompts(for: entry)
        let second = await waitForPrompts(coordinator)
        #expect(model.callCount == 1)
        #expect(offline.callCount == 1)
        #expect(second?.fallbackReason == .guardrail)
        _ = container
    }

    @Test func changedTextIsTriedAgain() async throws {
        let (entry, container) = try makeEntry("First version.")
        let (model, stack) = decliningStack(.refusal)
        let coordinator = ReflectionCoordinator(engine: stack, offlineEngine: StubEngine(prompts: ["Q?"]))
        coordinator.requestPrompts(for: entry)
        _ = await waitForPrompts(coordinator)

        entry.text = "Second version, written differently."
        coordinator.requestPrompts(for: entry)
        _ = await waitForPrompts(coordinator)
        #expect(model.callCount == 2)
        _ = container
    }

    @Test func transientFailuresAreRetried() async throws {
        let (entry, container) = try makeEntry("A long day.")
        let (model, stack) = decliningStack(.timeout)
        let coordinator = ReflectionCoordinator(engine: stack, offlineEngine: StubEngine(prompts: ["Q?"]))
        coordinator.requestPrompts(for: entry)
        _ = await waitForPrompts(coordinator)
        coordinator.requestPrompts(for: entry)
        _ = await waitForPrompts(coordinator)
        #expect(model.callCount == 2)
        _ = container
    }
}

// MARK: - Scheduler

struct ModelSchedulerTests {

    /// Records concurrent and total runs.
    final class Probe: Sendable {
        let active = Mutex(0)
        let maxActive = Mutex(0)
        let order = Mutex<[String]>([])

        func work(_ name: String, for duration: Duration) async throws -> String {
            active.withLock { value in
                value += 1
                let now = value
                maxActive.withLock { $0 = max($0, now) }
            }
            defer { active.withLock { $0 -= 1 } }
            order.withLock { $0.append(name) }
            try await Task.sleep(for: duration)
            return name
        }
    }

    @Test func runsOneAtATime() async throws {
        let scheduler = ModelScheduler(), probe = Probe()
        try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<5 {
                group.addTask {
                    try await scheduler.run(priority: .userInitiated) {
                        try await probe.work("\(index)", for: .milliseconds(20))
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(probe.maxActive.withLock { $0 } == 1)
        #expect(probe.order.withLock { $0.count } == 5)
    }

    @Test func userRequestsGoBeforeWaitingBackgroundWork() async throws {
        let scheduler = ModelScheduler(), probe = Probe()
        // Holder: a user request, so it isn't interrupted.
        let holder = Task { try await scheduler.run(priority: .userInitiated) { try await probe.work("holder", for: .milliseconds(150)) } }
        try await Task.sleep(for: .milliseconds(30))
        let background = Task { try await scheduler.run(priority: .background) { try await probe.work("background", for: .milliseconds(10)) } }
        try await Task.sleep(for: .milliseconds(30))
        let user = Task { try await scheduler.run(priority: .userInitiated) { try await probe.work("user", for: .milliseconds(10)) } }
        _ = try await (holder.value, background.value, user.value)
        #expect(probe.order.withLock { $0 } == ["holder", "user", "background"])
    }

    @Test func userRequestInterruptsRunningBackgroundWork() async throws {
        let scheduler = ModelScheduler(), probe = Probe()
        let background = Task {
            try await scheduler.run(priority: .background) { try await probe.work("background", for: .seconds(10)) }
        }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        let user = try await scheduler.run(priority: .userInitiated) { try await probe.work("user", for: .milliseconds(10)) }
        #expect(user == "user")
        #expect(ContinuousClock.now - start < .seconds(2), "User request waited for background work")
        await #expect(throws: CancellationError.self) { try await background.value }
    }

    @Test func cancelledWaiterLeavesTheQueue() async throws {
        let scheduler = ModelScheduler(), probe = Probe()
        let holder = Task { try await scheduler.run(priority: .userInitiated) { try await probe.work("holder", for: .milliseconds(100)) } }
        try await Task.sleep(for: .milliseconds(20))
        let waiter = Task { try await scheduler.run(priority: .userInitiated) { try await probe.work("cancelled", for: .milliseconds(10)) } }
        try await Task.sleep(for: .milliseconds(20))
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        _ = try await holder.value
        // The model is free again afterwards.
        let next = try await scheduler.run(priority: .background) { try await probe.work("next", for: .milliseconds(10)) }
        #expect(next == "next")
        #expect(!probe.order.withLock { $0 }.contains("cancelled"))
    }
}
