//
//  WeeklySummaryTests.swift
//  Journal-WhisperTests
//
//  Fingerprints, the offline template, saving and reusing summaries, and
//  discarding them when entries leave the journal.
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

private func date(_ day: Int, _ hour: Int = 12) -> Date {
    india.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
}

/// Mon 9 – Mon 16 Nov 2026.
private let week = WeekCalendar(calendar: india).week(containing: date(11))

private func snapshot(_ entries: [EntrySnapshot]) -> WeekSnapshot {
    WeekSnapshot(week: week, entries: entries, calendar: india)
}

private func entry(_ day: Int, _ mood: Mood?, text: String = "Some words.", updated: Date? = nil) -> EntrySnapshot {
    EntrySnapshot(createdAt: date(day), updatedAt: updated ?? date(day), text: text, mood: mood, gist: nil)
}

// MARK: - Snapshot & fingerprint

struct WeekSnapshotTests {

    @Test func keepsOnlyThisWeeksEntriesInOrder() {
        let snap = snapshot([entry(12, .calm), entry(8, .sad), entry(10, nil), entry(16, .joyful)])
        #expect(snap.entries.map(\.createdAt) == [date(10), date(12)])
        #expect(snap.daysWritten == 2)
    }

    @Test func fingerprintIsStable() {
        let entries = [entry(10, .calm), entry(12, .sad)]
        #expect(snapshot(entries).fingerprint == snapshot(entries.reversed()).fingerprint)
    }

    @Test func fingerprintChangesWithEditsMoodsAndMembership() {
        let base = snapshot([entry(10, .calm), entry(12, .sad)]).fingerprint
        #expect(snapshot([entry(10, .calm, updated: date(10, 18)), entry(12, .sad)]).fingerprint != base) // edited
        #expect(snapshot([entry(10, .content), entry(12, .sad)]).fingerprint != base)                     // re-tagged
        #expect(snapshot([entry(10, .calm)]).fingerprint != base)                                         // removed
        #expect(snapshot([entry(10, .calm), entry(12, .sad), entry(13, nil)]).fingerprint != base)        // added
        // An entry in another week doesn't matter.
        #expect(snapshot([entry(10, .calm), entry(12, .sad), entry(3, .joyful)]).fingerprint == base)
    }

    @Test @MainActor func journalEntriesFilterDeletedAndBlank() {
        let kept = JournalEntry(createdAt: date(10), text: "Kept")
        let blank = JournalEntry(createdAt: date(11))
        let deleted = JournalEntry(createdAt: date(12), text: "Gone")
        deleted.deletedAt = date(13)
        let snap = WeekSnapshot(week: week, journal: [kept, blank, deleted], calendar: india)
        #expect(snap.entries.map(\.text) == ["Kept"])
    }

    @Test @MainActor func staleGistIsIgnored() {
        let entry = JournalEntry(createdAt: date(10), text: "Walk")
        entry.gist = "A walk."
        entry.gistSourceUpdatedAt = entry.updatedAt
        #expect(WeekSnapshot(week: week, journal: [entry], calendar: india).entries.first?.gist == "A walk.")
        entry.updatedAt = date(10, 20)
        #expect(WeekSnapshot(week: week, journal: [entry], calendar: india).entries.first?.gist == nil)
    }

    @Test func crisisEntryNeedsSupport() {
        #expect(!snapshot([entry(10, .sad, text: "A hard day.")]).needsSupport)
        #expect(snapshot([entry(10, .sad, text: "I want to die.")]).needsSupport)
    }
}

// MARK: - Template

struct TemplateSummaryTests {

    @Test func writingSentence() {
        #expect(TemplateSummaryEngine.writingSentence(snapshot([entry(10, nil)])) == "You wrote once this week.")
        #expect(TemplateSummaryEngine.writingSentence(snapshot([entry(10, nil), entry(10, nil)]))
                == "You wrote 2 entries on one day this week.")
        #expect(TemplateSummaryEngine.writingSentence(snapshot([entry(10, nil), entry(11, nil)]))
                == "You wrote on 2 days this week.")
        #expect(TemplateSummaryEngine.writingSentence(snapshot([entry(10, nil), entry(10, nil), entry(11, nil)]))
                == "You wrote on 2 days this week, 3 entries in all.")
    }

    @Test func moodSentence() {
        func sentence(_ moods: [Mood?]) -> String {
            TemplateSummaryEngine.moodSentence(snapshot(moods.enumerated().map { entry(9 + $0.offset, $0.element) }).statistics)
        }
        #expect(sentence([nil]) == "None of this week's entries have a mood yet.")
        #expect(sentence([.calm]) == "You felt calm.")
        #expect(sentence([.calm, .calm, .sad]) == "Calm came up most often.")
        #expect(sentence([.calm, .sad, .joyful]).hasPrefix("Your moods ranged across "))
        // A tie isn't a favourite.
        #expect(sentence([.calm, .calm, .sad, .sad]).hasPrefix("Your moods ranged across "))
    }

    @Test func fullDraft() {
        let draft = TemplateSummaryEngine.draft(for: snapshot([
            entry(9, .anxious), entry(10, .sad), entry(14, .calm), entry(15, .calm),
        ]))
        #expect(draft.source == .offline)
        #expect(draft.text == "You wrote on 4 days this week. Calm came up most often. Things felt lighter toward the end of the week.")
        #expect(draft.closingQuestion != nil)
    }

    @Test func neverQuotesEntryText() {
        let secret = "Zanzibar-pineapple-secret"
        let draft = TemplateSummaryEngine.draft(for: snapshot([entry(10, .calm, text: secret)]))
        #expect(!draft.text.contains(secret))
        #expect(draft.closingQuestion?.contains(secret) != true)
    }

    @Test func sameWeekSameQuestion() {
        let snap = snapshot([entry(10, .calm)])
        #expect(TemplateSummaryEngine.closingQuestion(for: snap) == TemplateSummaryEngine.closingQuestion(for: snap))
    }

    @Test func noQuestionForWeeksNeedingSupport() {
        #expect(TemplateSummaryEngine.draft(for: snapshot([entry(10, .sad, text: "I want to die.")])).closingQuestion == nil)
    }
}

// MARK: - Saving, reusing, discarding

/// Counts calls and returns a fixed draft.
final class CountingSummaryEngine: SummaryEngine {
    let calls = Mutex(0)
    var count: Int { calls.withLock { $0 } }
    func summarize(_ week: WeekSnapshot) async throws -> SummaryDraft {
        calls.withLock { $0 += 1 }
        return SummaryDraft(text: "Summary of \(week.entries.count).", source: .ai)
    }
}

struct FailingSummaryEngine: SummaryEngine {
    func summarize(_ week: WeekSnapshot) async throws -> SummaryDraft {
        throw ReflectionError.generationFailed(.guardrail)
    }
}

@MainActor
struct WeeklySummaryStoreTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer.journal(inMemory: true)
    }

    private func insert(_ day: Int, _ text: String, mood: Mood? = nil, in context: ModelContext) -> JournalEntry {
        let entry = JournalEntry(createdAt: date(day), text: text)
        if let mood { entry.setUserMood(mood) }
        context.insert(entry)
        return entry
    }

    private func allEntries(_ context: ModelContext) throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>())
    }

    private func summaries(_ context: ModelContext) throws -> [WeeklySummary] {
        try context.fetch(FetchDescriptor<WeeklySummary>())
    }

    @Test func generatesSavesAndReuses() async throws {
        let container = try makeContainer(), context = container.mainContext
        _ = insert(10, "Walk", mood: .calm, in: context)
        let engine = CountingSummaryEngine()
        let coordinator = WeeklySummaryCoordinator(engine: engine)

        coordinator.refresh(week: week, entries: try allEntries(context), context: context, calendar: india)
        await coordinator.waitForCompletion()
        guard case .ready(let draft, 1, _) = coordinator.state else {
            Issue.record("Expected a summary, got \(coordinator.state)"); return
        }
        #expect(draft.text == "Summary of 1.")
        #expect(try summaries(context).count == 1)

        // Unchanged: the saved summary is reused without calling the engine.
        coordinator.refresh(week: week, entries: try allEntries(context), context: context, calendar: india)
        #expect(engine.count == 1)
        #expect(coordinator.state != .loading)
    }

    @Test func changesRegenerate() async throws {
        let container = try makeContainer(), context = container.mainContext
        let walk = insert(10, "Walk", mood: .calm, in: context)
        let engine = CountingSummaryEngine()
        let coordinator = WeeklySummaryCoordinator(engine: engine)
        coordinator.refresh(week: week, entries: try allEntries(context), context: context, calendar: india)
        await coordinator.waitForCompletion()

        walk.setUserMood(.joyful)
        coordinator.refresh(week: week, entries: try allEntries(context), context: context, calendar: india)
        await coordinator.waitForCompletion()
        #expect(engine.count == 2)
        #expect(try summaries(context).count == 1, "Updated in place, not duplicated")
    }

    @Test func emptyWeekRemovesSavedSummary() async throws {
        let container = try makeContainer(), context = container.mainContext
        let walk = insert(10, "Walk", in: context)
        let coordinator = WeeklySummaryCoordinator(engine: CountingSummaryEngine())
        coordinator.refresh(week: week, entries: try allEntries(context), context: context, calendar: india)
        await coordinator.waitForCompletion()

        walk.deletedAt = .now
        coordinator.refresh(week: week, entries: try allEntries(context), context: context, calendar: india)
        #expect(coordinator.state == .empty)
        #expect(try summaries(context).isEmpty)
    }

    @Test func engineFailureFallsBackToTemplate() async throws {
        let container = try makeContainer(), context = container.mainContext
        _ = insert(10, "Walk", mood: .calm, in: context)
        let coordinator = WeeklySummaryCoordinator(engine: FailingSummaryEngine())
        coordinator.refresh(week: week, entries: try allEntries(context), context: context, calendar: india)
        await coordinator.waitForCompletion()
        guard case .ready(let draft, _, _) = coordinator.state else {
            Issue.record("Expected a summary, got \(coordinator.state)"); return
        }
        #expect(draft.source == .offline)
        #expect(draft.text.hasPrefix("You wrote once this week."))
    }

    @Test func discardRemovesOnlyThatWeek() throws {
        let container = try makeContainer(), context = container.mainContext
        let draft = SummaryDraft(text: "x", source: .offline)
        context.insert(WeeklySummary(weekStart: week.start, draft: draft, fingerprint: "a", entryCount: 1))
        let lastWeek = WeekCalendar(calendar: india).week(offsetBy: -1, from: week)
        context.insert(WeeklySummary(weekStart: lastWeek.start, draft: draft, fingerprint: "b", entryCount: 1))

        WeeklySummary.discard(weekContaining: date(12), in: context, calendar: india)
        #expect(try summaries(context).map(\.weekStart) == [lastWeek.start])
    }

    @Test func summaryVersionAndFingerprintDecideCurrency() {
        let summary = WeeklySummary(weekStart: week.start, draft: SummaryDraft(text: "x", source: .offline),
                                    fingerprint: "abc", entryCount: 1)
        #expect(summary.isCurrent(for: "abc"))
        #expect(!summary.isCurrent(for: "abd"))
        summary.version = SummaryVersion.current - 1
        #expect(!summary.isCurrent(for: "abc"))
    }

    @Test func versionedContainerOpens() throws {
        let container = try makeContainer()
        #expect(container.schema.entities.map(\.name).sorted() == ["JournalEntry", "WeeklySummary"])
    }
}
