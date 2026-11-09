//
//  StreakCalculator.swift
//  Journal-Whisper
//
//  Writing streaks, computed fresh from entry dates every time and never
//  stored, so edits, deletions, restores and time-zone changes can't leave a
//  stale number behind.
//
//  Designed to encourage rather than punish: a streak stays alive until the
//  end of today even if the last entry was yesterday, and "days this week"
//  shows progress even after a streak resets.
//

import Foundation

nonisolated struct StreakSummary: Equatable, Sendable {
    /// Consecutive days with an entry, ending today or yesterday. 0 if neither.
    let current: Int
    /// The longest run of consecutive days ever.
    let longest: Int
    let wroteToday: Bool
    /// Days in the current week with at least one entry.
    let daysThisWeek: Int

    static let empty = StreakSummary(current: 0, longest: 0, wroteToday: false, daysThisWeek: 0)
}

nonisolated struct StreakCalculator: Sendable {
    let weeks: WeekCalendar

    init(calendar: Calendar = .current) {
        self.weeks = WeekCalendar(calendar: calendar)
    }

    /// - Parameter entryDates: creation dates of the entries that count. Use
    ///   `countedForStreaks` to filter out blank and deleted entries.
    func summary(entryDates: some Sequence<Date>, now: Date = .now) -> StreakSummary {
        let today = weeks.day(of: now)
        // Future-dated entries (clock changes) don't count yet.
        let days = Set(entryDates.lazy.filter { $0 <= now }.map(weeks.day(of:)))
        guard !days.isEmpty else { return .empty }

        let wroteToday = days.contains(today)
        let yesterday = weeks.previousDay(today)

        var current = 0
        if wroteToday || days.contains(yesterday) {
            var day = wroteToday ? today : yesterday
            while days.contains(day) {
                current += 1
                day = weeks.previousDay(day)
            }
        }

        var longest = 0, run = 0
        var previous: Date?
        for day in days.sorted() {
            run = previous.map { weeks.isDay(day, rightAfter: $0) } == true ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }

        let thisWeek = weeks.week(containing: now)
        let daysThisWeek = days.filter { thisWeek.contains($0) }.count

        return StreakSummary(current: current, longest: longest, wroteToday: wroteToday, daysThisWeek: daysThisWeek)
    }
}

extension Sequence where Element == JournalEntry {
    /// Creation dates of entries that count towards streaks: in the journal
    /// (not Recently Deleted) and not blank.
    var countedForStreaks: [Date] {
        filter { $0.deletedAt == nil && !$0.isBlank }.map(\.createdAt)
    }
}
