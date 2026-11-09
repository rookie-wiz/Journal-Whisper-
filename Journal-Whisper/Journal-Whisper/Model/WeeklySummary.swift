//
//  WeeklySummary.swift
//  Journal-Whisper
//
//  A saved summary of one week. Derived from that week's entries and tied to
//  them by a fingerprint: any edit, mood change, new, deleted or restored
//  entry makes it stale. Moving an entry to Recently Deleted (or deleting it)
//  removes the summary, since it may describe what was in that entry.
//

import Foundation
import SwiftData

@Model
final class WeeklySummary {
    #Unique<WeeklySummary>([\.weekStart])

    /// Start of the week (locale's first weekday, midnight).
    var weekStart: Date
    var text: String
    /// One reflection question for the week ahead, if any.
    var closingQuestion: String?
    /// Raw value of `Provenance`.
    var sourceRaw: String
    /// Raw value of `GenerationFailure`, when the offline template stepped in.
    var fallbackReasonRaw: String?
    var generatedAt: Date
    /// `SummaryVersion.current` when generated; older summaries are regenerated.
    var version: Int
    /// `SummaryFingerprint` of the week's entries when generated.
    var inputFingerprint: String
    var entryCount: Int

    init(weekStart: Date, draft: SummaryDraft, fingerprint: String, entryCount: Int, generatedAt: Date = .now) {
        self.weekStart = weekStart
        self.text = draft.text
        self.closingQuestion = draft.closingQuestion
        self.sourceRaw = draft.source.rawValue
        self.fallbackReasonRaw = draft.fallbackReason?.rawValue
        self.generatedAt = generatedAt
        self.version = SummaryVersion.current
        self.inputFingerprint = fingerprint
        self.entryCount = entryCount
    }

    var source: Provenance { Provenance(rawValue: sourceRaw) ?? .offline }
    var fallbackReason: GenerationFailure? { fallbackReasonRaw.flatMap(GenerationFailure.init(rawValue:)) }

    var draft: SummaryDraft {
        SummaryDraft(text: text, source: source, fallbackReason: fallbackReason, closingQuestion: closingQuestion)
    }

    /// Replaces the content with a newly generated draft.
    func update(with draft: SummaryDraft, fingerprint: String, entryCount: Int, generatedAt: Date = .now) {
        text = draft.text
        closingQuestion = draft.closingQuestion
        sourceRaw = draft.source.rawValue
        fallbackReasonRaw = draft.fallbackReason?.rawValue
        self.generatedAt = generatedAt
        version = SummaryVersion.current
        inputFingerprint = fingerprint
        self.entryCount = entryCount
    }

    func isCurrent(for fingerprint: String) -> Bool {
        inputFingerprint == fingerprint && version == SummaryVersion.current
    }

    // MARK: - Discarding

    /// Deletes the saved summary for the week containing `date`, if any. Call
    /// whenever an entry leaves the journal or its text changes, so a summary
    /// never keeps describing content the user removed.
    static func discard(weekContaining date: Date, in context: ModelContext, calendar: Calendar = .current) {
        let weekStart = WeekCalendar(calendar: calendar).week(containing: date).start
        let descriptor = FetchDescriptor<WeeklySummary>(predicate: #Predicate { $0.weekStart == weekStart })
        guard let summaries = try? context.fetch(descriptor), !summaries.isEmpty else { return }
        summaries.forEach(context.delete)
    }
}

/// Bump when the summary format, template or instructions change, so saved
/// summaries are regenerated.
nonisolated enum SummaryVersion {
    /// 2: template closing questions no longer mention "today".
    static let current = 2
}
