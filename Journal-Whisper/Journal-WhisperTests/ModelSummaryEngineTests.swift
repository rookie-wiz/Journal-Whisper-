//
//  ModelSummaryEngineTests.swift
//  Journal-WhisperTests
//
//  The model summary's step-down plan, driven by a scripted generator:
//  whole week → per-entry notes → template.
//

import Foundation
import Testing
import SwiftData
import Synchronization
@testable import Journal_Whisper

private let india: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.firstWeekday = 2
    return calendar
}()

private func date(_ day: Int) -> Date {
    india.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
}

private let week = WeekCalendar(calendar: india).week(containing: date(11))

private func entry(_ day: Int, _ text: String, _ mood: Mood? = .calm, gist: String? = nil) -> EntrySnapshot {
    EntrySnapshot(createdAt: date(day), updatedAt: date(day), text: text, mood: mood, gist: gist)
}

private func snapshot(_ entries: [EntrySnapshot]) -> WeekSnapshot {
    WeekSnapshot(week: week, entries: entries, calendar: india)
}

private let goodSummary = "This week you made time for slow walks and quiet reading, and you noticed how much calmer the evenings felt."

/// Answers by request kind and records every request.
final class FakeTextGenerator: SummaryTextGenerator {
    enum Kind { case summary, gist }
    typealias Responder = @Sendable (Kind, String) throws -> String

    let isAvailable: Bool
    let fitsWholeWeek: Bool
    private let responder: Responder
    let requests = Mutex<[(kind: Kind, prompt: String)]>([])

    init(available: Bool = true, fits: Bool = true, _ responder: @escaping Responder) {
        isAvailable = available
        fitsWholeWeek = fits
        self.responder = responder
    }

    func generate(instructions: String, prompt: String, maxTokens: Int, timeout: Duration) async throws -> String {
        let kind: Kind = instructions == SummaryInstructions.gist ? .gist : .summary
        requests.withLock { $0.append((kind, prompt)) }
        return try responder(kind, prompt)
    }

    func fits(instructions: String, prompt: String, reserve: Int) async -> Bool { fitsWholeWeek }

    func count(_ kind: Kind) -> Int { requests.withLock { $0.filter { $0.kind == kind }.count } }
    var prompts: [String] { requests.withLock { $0.map(\.prompt) } }
}

private func engine(_ generator: FakeTextGenerator) -> ModelSummaryEngine {
    ModelSummaryEngine(generator: generator, questionEngine: StubEngine(prompts: ["What will you carry forward?"]))
}

private let twoEntries = [entry(10, "Long walk by the river."), entry(12, "Read in the park all afternoon.")]

struct ModelSummaryLadderTests {

    @Test func wholeWeekInOneRequest() async throws {
        let generator = FakeTextGenerator { kind, _ in
            #expect(kind == .summary)
            return "Summary: **\(goodSummary)**"
        }
        let draft = try await engine(generator).summarize(snapshot(twoEntries))
        #expect(draft.source == .ai)
        #expect(draft.text == goodSummary, "Label and bold are stripped")
        #expect(draft.closingQuestion == "What will you carry forward?")
        #expect(generator.count(.summary) == 1 && generator.count(.gist) == 0)
        #expect(generator.prompts[0].contains("calm ×2"), "Mood facts come from code")
    }

    @Test func tooLongUsesNotes() async throws {
        let generator = FakeTextGenerator(fits: false) { kind, _ in
            kind == .gist ? "You spent time outside and felt calm." : goodSummary
        }
        let draft = try await engine(generator).summarize(snapshot(twoEntries))
        #expect(draft.source == .ai)
        #expect(generator.count(.gist) == 2)
        #expect(draft.gists.count == 2, "New notes are returned for caching")
        #expect(generator.prompts.last?.contains("Notes on each journal entry") == true)
    }

    @Test(arguments: [
        ("I'm sorry, but I can't help with that.", "refusal text"),
        ("This week you should talk to a therapist about your medication and your stress levels.", "unsafe text"),
    ])
    func declinedWholeWeekFallsBackToNotes(response: String, _ reason: String) async throws {
        let calls = Mutex(0)
        let generator = FakeTextGenerator { kind, _ in
            if kind == .gist { return "You had a quiet, calm day." }
            let first = calls.withLock { value in defer { value += 1 }; return value == 0 }
            return first ? response : goodSummary
        }
        let draft = try await engine(generator).summarize(snapshot(twoEntries))
        #expect(draft.text == goodSummary, "\(reason)")
        #expect(generator.count(.gist) == 2)
    }

    @Test func guardrailErrorFallsBackToNotesAndSkipsTheHardEntry() async throws {
        let entries = twoEntries + [entry(13, "A difficult entry about something heavy.", .sad)]
        let calls = Mutex(0)
        let generator = FakeTextGenerator { kind, prompt in
            if kind == .summary {
                let first = calls.withLock { value in defer { value += 1 }; return value == 0 }
                if first { throw ReflectionError.generationFailed(.guardrail) }
                return goodSummary
            }
            if prompt.contains("difficult entry") { throw ReflectionError.generationFailed(.guardrail) }
            return "You had a calm day outside."
        }
        let draft = try await engine(generator).summarize(snapshot(entries))
        #expect(draft.source == .ai)
        #expect(draft.gists.count == 2, "The declined entry gets no note")
        #expect(generator.prompts.last?.contains("difficult") == false)
    }

    @Test func tooFewNotesGivesUpWithTheFirstReason() async throws {
        let generator = FakeTextGenerator { kind, _ in
            if kind == .summary { throw ReflectionError.generationFailed(.refusal) }
            return "I'm sorry, I can't summarise this."
        }
        await #expect(throws: ReflectionError.generationFailed(.refusal)) {
            try await engine(generator).summarize(snapshot(twoEntries))
        }
    }

    @Test(arguments: [GenerationFailure.timeout, .unavailable, .busy, .unsupportedLanguage])
    func failuresNotesCantFixSkipStraightToTemplate(failure: GenerationFailure) async throws {
        let generator = FakeTextGenerator { _, _ in throw ReflectionError.generationFailed(failure) }
        await #expect(throws: ReflectionError.generationFailed(failure)) {
            try await engine(generator).summarize(snapshot(twoEntries))
        }
        #expect(generator.count(.gist) == 0)
    }

    @Test func cachedNotesAreReused() async throws {
        let entries = [entry(10, "Walk.", gist: "You walked by the river."), entry(12, "Park.")]
        let generator = FakeTextGenerator(fits: false) { kind, _ in
            kind == .gist ? "You read in the park and felt calm." : goodSummary
        }
        let draft = try await engine(generator).summarize(snapshot(entries))
        #expect(generator.count(.gist) == 1)
        #expect(draft.gists.count == 1)
        #expect(generator.prompts.last?.contains("You walked by the river.") == true)
    }

    @Test func crisisEntriesNeverReachTheModel() async throws {
        let entries = twoEntries + [entry(13, "Some days I want to die.", .sad)]
        let generator = FakeTextGenerator { _, _ in goodSummary }
        let draft = try await engine(generator).summarize(snapshot(entries))
        #expect(!generator.prompts.contains { $0.contains("want to die") })
        #expect(draft.closingQuestion == nil, "Weeks needing support get no question")
    }

    @Test func tooFewUsableEntriesUseTemplateWithoutAsking() async throws {
        let generator = FakeTextGenerator { _, _ in goodSummary }
        let draft = try await engine(generator).summarize(snapshot([entry(10, "Just one entry.")]))
        #expect(draft.source == .offline)
        #expect(draft.fallbackReason == nil, "Not a failure, so no note")
        #expect(generator.prompts.isEmpty)
    }

    @Test func unavailableModelThrows() async {
        let generator = FakeTextGenerator(available: false) { _, _ in goodSummary }
        await #expect(throws: ReflectionError.generationFailed(.unavailable)) {
            try await engine(generator).summarize(snapshot(twoEntries))
        }
    }

    @Test func fallbackWrapperUsesTemplateAndRecordsReason() async throws {
        let generator = FakeTextGenerator { _, _ in throw ReflectionError.generationFailed(.timeout) }
        let draft = try await FallbackSummaryEngine(primary: engine(generator)).summarize(snapshot(twoEntries))
        #expect(draft.source == .offline)
        #expect(draft.fallbackReason == .timeout)
        #expect(draft.text.hasPrefix("You wrote on 2 days this week."))
    }
}

struct SummarySafetyTests {

    @Test(arguments: [
        "I'm sorry, but I can't help with that.",
        "I can’t summarise this content.",
        "Sorry, I cannot do that.",
        "Unfortunately, I am not able to help.",
        "As an AI, I don't have feelings, but here's a summary.",
    ])
    func detectsRefusals(text: String) {
        #expect(SafetyGate.looksLikeRefusal(text))
    }

    @Test func ordinaryProseIsNotARefusal() {
        #expect(!SafetyGate.looksLikeRefusal(goodSummary))
        #expect(!SafetyGate.looksLikeRefusal("You couldn't sleep on Tuesday, but the weekend felt lighter."))
    }

    @Test func acceptableSummaries() {
        #expect(SafetyGate.isAcceptableSummary(goodSummary))
        #expect(!SafetyGate.isAcceptableSummary("Too short."))
        #expect(!SafetyGate.isAcceptableSummary("This week sounded hard, and you might want to ask your doctor about medication."))
        #expect(!SafetyGate.isAcceptableSummary("This week was busy, and you should take a break and rest more often."))
        #expect(!SafetyGate.isAcceptableSummary(String(repeating: "A long sentence about the week. ", count: 40)))
    }

    @Test func sanitizeProse() {
        #expect(SafetyGate.sanitizeProse("  Summary:  \"You   walked.\" ") == "You walked.")
        #expect(SafetyGate.sanitizeProse("**You** read a lot.") == "You read a lot.")
    }

    @Test func restoresCapitalisationOnlyWhenAllLowercase() {
        #expect(SafetyGate.restoreCapitalisation("you felt calm on sunday. then i rested in june!")
                == "You felt calm on Sunday. Then I rested in June!")
        // Text with any capitals is left exactly as written.
        #expect(SafetyGate.restoreCapitalisation("You met maya on sunday.") == "You met maya on sunday.")
        #expect(SafetyGate.restoreCapitalisation("") == "")
    }

    @Test func lowercaseModelOutputIsFixedBeforeShowing() async throws {
        let generator = FakeTextGenerator { _, _ in goodSummary.lowercased() + " monday felt lighter." }
        let draft = try await engine(generator).summarize(snapshot(twoEntries))
        #expect(draft.text.hasPrefix("This week you made time"))
        #expect(draft.text.hasSuffix("Monday felt lighter."))
    }

    @Test func gists() {
        #expect(SafetyGate.isAcceptableGist("You walked by the river and felt calm."))
        #expect(!SafetyGate.isAcceptableGist("I'm sorry, I can't help with that."))
        #expect(!SafetyGate.isAcceptableGist("Calm."))
    }
}

struct SummaryFooterTests {
    private func footer(_ source: Provenance, _ reason: GenerationFailure?) -> String {
        WeeklySummaryCard.footer(draft: SummaryDraft(text: "x", source: source, fallbackReason: reason), entryCount: 3)
    }

    @Test func variants() {
        #expect(footer(.ai, nil) == "Based on 3 entries")
        #expect(footer(.offline, nil) == "Based on 3 entries · from your moods and writing days")
        #expect(footer(.offline, .timeout) == "Based on 3 entries · from your moods and writing days for now")
        #expect(footer(.offline, .refusal).contains("wasn't available for this week"))
        for word in ["error", "failed", "refused", "blocked", "guardrail"] {
            #expect(!footer(.offline, .refusal).localizedCaseInsensitiveContains(word))
        }
    }
}

@MainActor
struct SummaryCoordinatorModelTests {

    @Test func gistsAreCachedOnTheirEntries() async throws {
        let container = try ModelContainer.journal(inMemory: true), context = container.mainContext
        let walk = JournalEntry(createdAt: date(10), text: "Walk by the river.")
        let park = JournalEntry(createdAt: date(12), text: "Reading in the park.")
        [walk, park].forEach(context.insert)
        let generator = FakeTextGenerator(fits: false) { kind, prompt in
            kind == .gist ? (prompt.contains("river") ? "You walked by the river." : "You read in the park.") : goodSummary
        }
        let coordinator = WeeklySummaryCoordinator(engine: engine(generator), modelAvailable: { true })
        coordinator.refresh(week: week, entries: [walk, park], context: context, calendar: india)
        await coordinator.waitForCompletion()

        #expect(walk.gist == "You walked by the river.")
        #expect(walk.gistSourceUpdatedAt == walk.updatedAt)
        #expect(park.gist == "You read in the park.")
    }

    @Test func offlineSummaryRetriedLaterWhenModelIsBack() {
        let summary = WeeklySummary(
            weekStart: week.start,
            draft: SummaryDraft(text: "x", source: .offline, fallbackReason: .timeout),
            fingerprint: "f", entryCount: 2, generatedAt: date(10)
        )
        let available = WeeklySummaryCoordinator(engine: TemplateSummaryEngine(), modelAvailable: { true })
        let unavailable = WeeklySummaryCoordinator(engine: TemplateSummaryEngine(), modelAvailable: { false })
        let soon = date(10).addingTimeInterval(60), later = date(10).addingTimeInterval(3600)

        #expect(!available.shouldRetry(summary, now: soon), "Not on every visit")
        #expect(available.shouldRetry(summary, now: later))
        #expect(!unavailable.shouldRetry(summary, now: later))

        summary.fallbackReasonRaw = GenerationFailure.refusal.rawValue
        #expect(!available.shouldRetry(summary, now: later), "A decline would repeat")
        summary.sourceRaw = Provenance.ai.rawValue
        summary.fallbackReasonRaw = nil
        #expect(!available.shouldRetry(summary, now: later))
    }
}
