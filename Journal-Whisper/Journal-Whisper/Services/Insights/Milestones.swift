//
//  Milestones.swift
//  Journal-Whisper
//
//  Gentle milestone badges. Earned once, kept forever: deleting entries or a
//  broken streak never takes a badge away (only Delete All Journal Data does).
//  No points, levels or leaderboards: research on mental-health apps finds
//  those add pressure without improving outcomes, especially for people in distress.
//

import Foundation
import Observation

nonisolated enum Milestone: String, CaseIterable, Codable, Identifiable, Sendable {
    case firstEntry
    case namedAFeeling
    case threeDays
    case tenEntries
    case sevenDays
    case thirtyEntries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstEntry: String(localized: "First page")
        case .namedAFeeling: String(localized: "Named a feeling")
        case .threeDays: String(localized: "Three-day glow")
        case .tenEntries: String(localized: "Ten pages")
        case .sevenDays: String(localized: "A week of pages")
        case .thirtyEntries: String(localized: "Thirty pages")
        }
    }

    /// How it's earned, said kindly.
    var detail: String {
        switch self {
        case .firstEntry: String(localized: "Wrote your first entry")
        case .namedAFeeling: String(localized: "Added a mood to an entry")
        case .threeDays: String(localized: "Wrote three days in a row")
        case .tenEntries: String(localized: "Wrote ten entries")
        case .sevenDays: String(localized: "Wrote seven days in a row")
        case .thirtyEntries: String(localized: "Wrote thirty entries")
        }
    }

    var symbol: String {
        switch self {
        case .firstEntry: "pencil.line"
        case .namedAFeeling: "face.smiling"
        case .threeDays: "flame"
        case .tenEntries: "book"
        case .sevenDays: "sun.max"
        case .thirtyEntries: "books.vertical"
        }
    }

    /// Facts the milestones are judged on.
    struct Progress: Equatable, Sendable {
        var entryCount: Int
        var longestStreak: Int
        var hasMood: Bool
    }

    func isReached(by progress: Progress) -> Bool {
        switch self {
        case .firstEntry: progress.entryCount >= 1
        case .namedAFeeling: progress.hasMood
        case .threeDays: progress.longestStreak >= 3
        case .tenEntries: progress.entryCount >= 10
        case .sevenDays: progress.longestStreak >= 7
        case .thirtyEntries: progress.entryCount >= 30
        }
    }
}

/// Earned milestones, kept in UserDefaults on this device.
@Observable
final class MilestoneStore {
    private(set) var earned: [Milestone: Date]
    /// Set when a badge is newly earned, for a short celebration; cleared after.
    var justEarned: Milestone?

    private let defaults: UserDefaults
    static let key = "earnedMilestones"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.dictionary(forKey: Self.key) as? [String: Date]) ?? [:]
        earned = Dictionary(uniqueKeysWithValues: stored.compactMap { key, date in
            Milestone(rawValue: key).map { ($0, date) }
        })
    }

    func isEarned(_ milestone: Milestone) -> Bool { earned[milestone] != nil }

    /// Records any newly reached milestones and returns them. Never removes one.
    @discardableResult
    func update(with progress: Milestone.Progress, now: Date = .now) -> [Milestone] {
        let new = Milestone.allCases.filter { !isEarned($0) && $0.isReached(by: progress) }
        guard !new.isEmpty else { return [] }
        for milestone in new { earned[milestone] = now }
        save()
        // Celebrate the biggest one if several arrive at once.
        justEarned = new.last
        return new
    }

    /// Only for Delete All Journal Data.
    func reset() {
        earned = [:]
        justEarned = nil
        defaults.removeObject(forKey: Self.key)
    }

    private func save() {
        defaults.set(Dictionary(uniqueKeysWithValues: earned.map { ($0.key.rawValue, $0.value) }), forKey: Self.key)
    }
}

extension Sequence where Element == JournalEntry {
    /// Progress towards milestones from entries in the journal.
    var milestoneProgress: Milestone.Progress {
        let counted = filter { $0.deletedAt == nil && !$0.isBlank }
        let summary = StreakCalculator().summary(entryDates: counted.map(\.createdAt))
        return Milestone.Progress(
            entryCount: counted.count,
            longestStreak: summary.longest,
            hasMood: counted.contains { $0.mood != nil }
        )
    }
}
