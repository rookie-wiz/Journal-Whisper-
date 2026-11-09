//
//  WeekSnapshot.swift
//  Journal-Whisper
//
//  A Sendable copy of one week's entries: what summary engines read, plus a
//  fingerprint that changes whenever anything a summary depends on changes.
//

import Foundation
import CryptoKit

nonisolated struct EntrySnapshot: Sendable, Equatable {
    let createdAt: Date
    let updatedAt: Date
    /// Title and text together.
    let text: String
    let mood: Mood?
    /// The cached one-line gist, only if it was written from this version of the entry.
    let gist: String?
}

nonisolated struct WeekSnapshot: Sendable {
    let week: DateInterval
    /// Entries in the week that are in the journal and not blank, oldest first.
    let entries: [EntrySnapshot]
    let statistics: MoodStatistics
    let daysWritten: Int
    /// Changes when an entry is added, edited, re-tagged, deleted or restored.
    let fingerprint: String

    init(week: DateInterval, entries: [EntrySnapshot], calendar: Calendar = .current) {
        let inWeek = entries
            .filter { week.contains($0.createdAt) && $0.createdAt < week.end }
            .sorted { $0.createdAt < $1.createdAt }
        let weeks = WeekCalendar(calendar: calendar)
        self.week = week
        self.entries = inWeek
        statistics = MoodStatistics(
            points: inWeek.map { MoodPoint(date: $0.createdAt, mood: $0.mood) },
            range: week,
            calendar: calendar
        )
        daysWritten = Set(inWeek.map { weeks.day(of: $0.createdAt) }).count
        fingerprint = Self.fingerprint(of: inWeek)
    }

    /// True if any entry has crisis wording. Those weeks get the support card,
    /// and their crisis entries are never sent to the model.
    var needsSupport: Bool {
        entries.contains { SafetyGate.assess($0.text) == .needsSupport }
    }

    /// SHA-256 of each entry's creation time, edit time and mood. Text isn't
    /// hashed directly: any text edit already moves `updatedAt`.
    static func fingerprint(of entries: [EntrySnapshot]) -> String {
        let canonical = entries.map {
            "\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.mood?.rawValue ?? "-")"
        }.joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension WeekSnapshot {
    /// Builds a snapshot from journal entries (main actor: reads SwiftData models).
    init(week: DateInterval, journal: some Sequence<JournalEntry>, calendar: Calendar = .current) {
        let snapshots = journal
            .filter { $0.deletedAt == nil && !$0.isBlank }
            .map { entry in
                EntrySnapshot(
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt,
                    text: entry.reflectionText,
                    mood: entry.mood,
                    gist: entry.gistSourceUpdatedAt == entry.updatedAt ? entry.gist : nil
                )
            }
        self.init(week: week, entries: snapshots, calendar: calendar)
    }
}
