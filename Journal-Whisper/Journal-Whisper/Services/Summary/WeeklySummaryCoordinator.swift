//
//  WeeklySummaryCoordinator.swift
//  Journal-Whisper
//
//  Shows the summary for one week: the saved one if it still matches the
//  entries, otherwise a freshly generated one (then saved). Summaries are only
//  made when a week is viewed, never in the background.
//

import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
final class WeeklySummaryCoordinator {
    enum State: Equatable {
        case idle
        /// No entries in this week.
        case empty
        case loading
        case ready(SummaryDraft, entryCount: Int, generatedAt: Date)
    }

    private(set) var state: State = .idle
    /// Some entry this week has crisis wording: show the support card with the summary.
    private(set) var needsSupport = false

    private let engine: any SummaryEngine
    private var task: Task<Void, Never>?
    /// Fingerprint of the most recent request, so a slow, outdated result is dropped.
    private var latestFingerprint: String?

    init(engine: any SummaryEngine) {
        self.engine = engine
    }

    func refresh(week: DateInterval, entries: [JournalEntry], context: ModelContext, calendar: Calendar = .current) {
        let snapshot = WeekSnapshot(week: week, journal: entries, calendar: calendar)
        latestFingerprint = snapshot.fingerprint
        needsSupport = snapshot.needsSupport
        task?.cancel()

        let stored = Self.stored(weekStart: week.start, in: context)
        guard !snapshot.entries.isEmpty else {
            // Nothing left to describe: don't keep an old summary around.
            if let stored { context.delete(stored) }
            state = .empty
            return
        }
        if let stored, stored.isCurrent(for: snapshot.fingerprint) {
            state = .ready(stored.draft, entryCount: stored.entryCount, generatedAt: stored.generatedAt)
            return
        }

        state = .loading
        task = Task { [weak self, engine] in
            var draft: SummaryDraft
            do {
                draft = try await engine.summarize(snapshot)
            } catch is CancellationError {
                return
            } catch {
                // Last resort if the engine stack itself failed.
                draft = TemplateSummaryEngine.draft(for: snapshot)
                draft.fallbackReason = .other
            }
            guard !Task.isCancelled, let self, self.latestFingerprint == snapshot.fingerprint else { return }
            self.save(draft, for: snapshot, in: context)
        }
    }

    /// Awaits the current generation, for tests.
    func waitForCompletion() async {
        await task?.value
    }

    private func save(_ draft: SummaryDraft, for snapshot: WeekSnapshot, in context: ModelContext) {
        let now = Date.now
        if let stored = Self.stored(weekStart: snapshot.week.start, in: context) {
            stored.update(with: draft, fingerprint: snapshot.fingerprint, entryCount: snapshot.entries.count, generatedAt: now)
        } else {
            context.insert(WeeklySummary(weekStart: snapshot.week.start, draft: draft,
                                         fingerprint: snapshot.fingerprint, entryCount: snapshot.entries.count,
                                         generatedAt: now))
        }
        try? context.save()
        state = .ready(draft, entryCount: snapshot.entries.count, generatedAt: now)
    }

    private static func stored(weekStart: Date, in context: ModelContext) -> WeeklySummary? {
        var descriptor = FetchDescriptor<WeeklySummary>(predicate: #Predicate { $0.weekStart == weekStart })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

extension EnvironmentValues {
    /// The engine Insights uses for weekly summaries. Offline template for now.
    @Entry var summaryEngine: any SummaryEngine = TemplateSummaryEngine()
}
