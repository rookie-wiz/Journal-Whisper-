//
//  JournalEntry.swift
//  Journal-Whisper
//

import Foundation
import SwiftData

@Model
final class JournalEntry {
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var text: String
    /// Set when the entry is moved to Recently Deleted; nil while it's in the journal.
    var deletedAt: Date?

    // Mood fields are stored as primitives (not enums or a Codable struct) so
    // they work in #Predicate / @Query for the Week 3 charts. All optional, so
    // existing stores migrate automatically.
    /// Raw value of `Mood`; use `mood` instead.
    var moodRaw: String?
    /// How strongly the mood was felt, within `Mood.intensityRange`.
    var moodIntensity: Int?
    /// Raw value of `MoodSource`; use `moodSource` instead.
    var moodSourceRaw: String?

    /// How long entries stay in Recently Deleted before being purged.
    static let retentionDays = 30

    init(createdAt: Date = .now, title: String = "", text: String = "") {
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.title = title
        self.text = text
    }

    /// True when the user hasn't written anything worth keeping.
    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The title if set, otherwise the first line of the text.
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return firstLine ?? "Untitled"
    }

    /// When a deleted entry will be permanently removed.
    var purgeDate: Date? {
        deletedAt.flatMap { Calendar.current.date(byAdding: .day, value: Self.retentionDays, to: $0) }
    }

    /// Whole days left before a deleted entry is purged.
    var daysUntilPurge: Int {
        guard let purgeDate else { return Self.retentionDays }
        let seconds = purgeDate.timeIntervalSinceNow
        return max(0, Int((seconds / 86_400).rounded(.up)))
    }

    /// Permanently removes entries that have been in Recently Deleted longer than the retention period.
    static func purgeExpired(in context: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) else { return }
        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { entry in
                if let deletedAt = entry.deletedAt { deletedAt < cutoff } else { false }
            }
        )
        guard let expired = try? context.fetch(descriptor), !expired.isEmpty else { return }
        expired.forEach(context.delete)
        try? context.save()
    }

    // MARK: - Mood

    var mood: Mood? { moodRaw.flatMap(Mood.init(rawValue:)) }
    var moodSource: MoodSource? { moodSourceRaw.flatMap(MoodSource.init(rawValue:)) }

    /// Sets the mood the user picked. This always wins over suggestions.
    func setUserMood(_ mood: Mood, intensity: Int = Mood.defaultIntensity) {
        moodRaw = mood.rawValue
        moodIntensity = Self.clampedIntensity(intensity)
        moodSourceRaw = MoodSource.user.rawValue
    }

    /// Applies a mood suggested by the model or the fallback. Does nothing if the
    /// user already chose a mood. Returns true if the suggestion was applied.
    @discardableResult
    func applySuggestedMood(_ mood: Mood, intensity: Int, source: MoodSource) -> Bool {
        guard source != .user, moodSource != .user else { return false }
        moodRaw = mood.rawValue
        moodIntensity = Self.clampedIntensity(intensity)
        moodSourceRaw = source.rawValue
        return true
    }

    /// Removes the mood. After the user clears it, suggestions may tag the entry again.
    func clearMood() {
        moodRaw = nil
        moodIntensity = nil
        moodSourceRaw = nil
    }

    private static func clampedIntensity(_ value: Int) -> Int {
        min(max(value, Mood.intensityRange.lowerBound), Mood.intensityRange.upperBound)
    }

    /// A short preview of the text for list rows.
    var preview: String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
