//
//  MoodStatistics.swift
//  Journal-Whisper
//
//  Mood counts for a range of days: per day (for the charts), in total, the
//  most frequent mood, and whether the period got lighter or heavier. Feeds
//  the mood charts and the offline weekly summary; no AI involved.
//

import Foundation

/// One entry's mood at a point in time. Entries without a mood are counted as untagged.
nonisolated struct MoodPoint: Sendable, Equatable {
    let date: Date
    let mood: Mood?
}

nonisolated struct MoodStatistics: Sendable {

    struct Day: Identifiable, Sendable, Equatable {
        let day: Date
        let counts: [Mood: Int]
        let untagged: Int
        var id: Date { day }
        var entryCount: Int { counts.values.reduce(0, +) + untagged }
    }

    /// One bar segment for Swift Charts: how many entries on `day` had `mood`.
    struct DayMoodCount: Identifiable, Sendable, Equatable {
        let day: Date
        let mood: Mood
        let count: Int
        var id: String { "\(day.timeIntervalSinceReferenceDate)-\(mood.rawValue)" }
    }

    enum Trend: String, Sendable, Equatable {
        /// More positive moods in the second half of the period.
        case lighter
        case heavier
        case steady
    }

    let range: DateInterval
    /// Every day in the range, including days with no entries.
    let days: [Day]
    let totals: [Mood: Int]
    let untaggedCount: Int
    let entryCount: Int
    /// Most frequent mood; on a tie, the one that appeared most recently. Nil if nothing is tagged.
    let dominantMood: Mood?
    /// Nil when there's too little tagged data to say.
    let trend: Trend?

    /// Tagged entries needed before a trend is reported, and per half of the period.
    static let minimumForTrend = 3
    /// Change in average valence (from -1 to +1) that must be exceeded to count as
    /// lighter or heavier. Strict, so one neutral day after a calm one is "steady".
    static let trendThreshold = 0.5

    init(points: [MoodPoint], range: DateInterval, calendar: Calendar = .current) {
        let weeks = WeekCalendar(calendar: calendar)
        let inRange = points.filter { range.contains($0.date) && $0.date < range.end }
        self.range = range

        var byDay: [Date: [MoodPoint]] = [:]
        for point in inRange { byDay[weeks.day(of: point.date), default: []].append(point) }
        days = weeks.days(in: range).map { day in
            let points = byDay[day] ?? []
            var counts: [Mood: Int] = [:]
            for case let mood? in points.map(\.mood) { counts[mood, default: 0] += 1 }
            return Day(day: day, counts: counts, untagged: points.filter { $0.mood == nil }.count)
        }

        var totals: [Mood: Int] = [:]
        var lastSeen: [Mood: Date] = [:]
        for point in inRange {
            guard let mood = point.mood else { continue }
            totals[mood, default: 0] += 1
            lastSeen[mood] = max(lastSeen[mood] ?? .distantPast, point.date)
        }
        self.totals = totals
        untaggedCount = inRange.filter { $0.mood == nil }.count
        entryCount = inRange.count
        dominantMood = totals.max { a, b in
            (a.value, lastSeen[a.key]!) < (b.value, lastSeen[b.key]!)
        }?.key
        trend = Self.trend(of: inRange, in: range)
    }

    /// Non-zero segments for a stacked bar chart, in a stable mood order.
    var dayMoodCounts: [DayMoodCount] {
        days.flatMap { day in
            Mood.allCases.compactMap { mood in
                day.counts[mood].map { DayMoodCount(day: day.day, mood: mood, count: $0) }
            }
        }
    }

    /// Moods that appeared, most frequent first (ties in `Mood.allCases` order).
    var rankedMoods: [(mood: Mood, count: Int)] {
        Mood.allCases.compactMap { mood in totals[mood].map { (mood, $0) } }
            .sorted { $0.count > $1.count }
    }

    /// Compares average valence in the first and second half of the period.
    private static func trend(of points: [MoodPoint], in range: DateInterval) -> Trend? {
        let tagged = points.compactMap { point in point.mood.map { (point.date, $0.valence.weight) } }
        guard tagged.count >= minimumForTrend else { return nil }
        let midpoint = range.start.addingTimeInterval(range.duration / 2)
        let first = tagged.filter { $0.0 < midpoint }.map(\.1)
        let second = tagged.filter { $0.0 >= midpoint }.map(\.1)
        guard !first.isEmpty, !second.isEmpty else { return nil }
        let change = second.reduce(0, +) / Double(second.count) - first.reduce(0, +) / Double(first.count)
        if change > trendThreshold { return .lighter }
        if change < -trendThreshold { return .heavier }
        return .steady
    }
}

extension Sequence where Element == JournalEntry {
    /// Mood points for entries in the journal (not Recently Deleted, not blank).
    var moodPoints: [MoodPoint] {
        filter { $0.deletedAt == nil && !$0.isBlank }.map { MoodPoint(date: $0.createdAt, mood: $0.mood) }
    }
}
