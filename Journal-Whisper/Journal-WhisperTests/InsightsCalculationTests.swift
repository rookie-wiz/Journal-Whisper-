//
//  InsightsCalculationTests.swift
//  Journal-WhisperTests
//
//  Week boundaries, streaks and mood statistics, with fixed calendars so the
//  results don't depend on the machine's locale or time zone.
//

import Foundation
import Testing
@testable import Journal_Whisper

/// Monday-first Gregorian calendar in India (no daylight saving).
private let india: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.firstWeekday = 2
    return calendar
}()

/// Sunday-first US calendar with daylight saving (2026: Mar 8 and Nov 1).
private let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    calendar.firstWeekday = 1
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0,
                  in calendar: Calendar = india) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

// MARK: - WeekCalendar

struct WeekCalendarTests {

    @Test func mondayFirstWeek() {
        // Wednesday 11 Nov 2026 → Mon 9 to Mon 16.
        let week = WeekCalendar(calendar: india).week(containing: date(2026, 11, 11))
        #expect(week.start == date(2026, 11, 9, 0))
        #expect(week.end == date(2026, 11, 16, 0))
    }

    @Test func sundayFirstWeek() {
        let week = WeekCalendar(calendar: newYork).week(containing: date(2026, 11, 11, in: newYork))
        #expect(week.start == date(2026, 11, 8, 0, in: newYork))
    }

    @Test func weekHasSevenDays() {
        let weeks = WeekCalendar(calendar: india)
        #expect(weeks.days(in: weeks.week(containing: date(2026, 11, 11))).count == 7)
    }

    @Test func daylightSavingWeekStillHasSevenDays() {
        // Week of 1 Nov 2026 in New York has a 25-hour Sunday.
        let weeks = WeekCalendar(calendar: newYork)
        let days = weeks.days(in: weeks.week(containing: date(2026, 11, 3, in: newYork)))
        #expect(days.count == 7)
        #expect(days.first == date(2026, 11, 1, 0, in: newYork))
        #expect(days.allSatisfy { newYork.component(.hour, from: $0) == 0 })
    }

    @Test func weekOffsets() {
        let weeks = WeekCalendar(calendar: india)
        let week = weeks.week(containing: date(2026, 11, 11))
        #expect(weeks.week(offsetBy: -1, from: week).start == date(2026, 11, 2, 0))
        #expect(weeks.week(offsetBy: 1, from: week).start == date(2026, 11, 16, 0))
    }

    @Test func yearBoundaryWeek() {
        // Thu 31 Dec 2026 falls in the week starting Mon 28 Dec.
        let weeks = WeekCalendar(calendar: india)
        let week = weeks.week(containing: date(2026, 12, 31))
        #expect(week.start == date(2026, 12, 28, 0))
        #expect(weeks.days(in: week).last == date(2027, 1, 3, 0))
    }

    @Test func monthDays() {
        let weeks = WeekCalendar(calendar: india)
        #expect(weeks.days(in: weeks.month(containing: date(2026, 2, 10))).count == 28)
    }
}

// MARK: - Streaks

struct StreakCalculatorTests {
    private let calculator = StreakCalculator(calendar: india)
    /// Wednesday 11 Nov 2026, 8 pm.
    private let now = date(2026, 11, 11, 20)

    @Test func noEntries() {
        #expect(calculator.summary(entryDates: [], now: now) == .empty)
    }

    @Test func todayOnly() {
        let summary = calculator.summary(entryDates: [date(2026, 11, 11, 9)], now: now)
        #expect(summary == StreakSummary(current: 1, longest: 1, wroteToday: true, daysThisWeek: 1))
    }

    @Test func streakSurvivesUntilEndOfToday() {
        // Wrote Mon and Tue, not yet today: still a 2-day streak.
        let summary = calculator.summary(entryDates: [date(2026, 11, 9), date(2026, 11, 10)], now: now)
        #expect(summary.current == 2)
        #expect(!summary.wroteToday)
    }

    @Test func streakEndsAfterAMissedDay() {
        // Last entry Monday; Tuesday missed.
        let summary = calculator.summary(entryDates: [date(2026, 11, 8), date(2026, 11, 9)], now: now)
        #expect(summary.current == 0)
        #expect(summary.longest == 2)
    }

    @Test func severalEntriesInADayCountOnce() {
        let dates = [date(2026, 11, 11, 8), date(2026, 11, 11, 13), date(2026, 11, 11, 19)]
        #expect(calculator.summary(entryDates: dates, now: now).current == 1)
    }

    @Test func longestIsKeptAfterReset() {
        let earlier = (1...5).map { date(2026, 10, $0) }       // 5-day run in October
        let recent = [date(2026, 11, 10), date(2026, 11, 11)]  // current 2-day run
        let summary = calculator.summary(entryDates: earlier + recent, now: now)
        #expect(summary.current == 2)
        #expect(summary.longest == 5)
    }

    @Test func entriesNearMidnightLandOnTheirOwnDay() {
        let dates = [date(2026, 11, 9, 23, 59), date(2026, 11, 10, 0, 1)]
        let summary = calculator.summary(entryDates: dates, now: now)
        #expect(summary.current == 2)
        #expect(summary.daysThisWeek == 2)
    }

    @Test func futureEntriesDontCount() {
        let summary = calculator.summary(entryDates: [date(2026, 11, 12)], now: now)
        #expect(summary == .empty)
    }

    @Test func daysThisWeekResetsOnNewWeek() {
        // Sat 7 and Sun 8 Nov belong to last week (Monday-first); Mon 9 to this week.
        let dates = [date(2026, 11, 7), date(2026, 11, 8), date(2026, 11, 9)]
        let summary = calculator.summary(entryDates: dates, now: now)
        #expect(summary.daysThisWeek == 1)
        #expect(summary.longest == 3)
    }

    @Test func streakAcrossDaylightSavingChange() {
        // 31 Oct → 1 Nov (25-hour day) → 2 Nov in New York.
        let calculator = StreakCalculator(calendar: newYork)
        let dates = [date(2026, 10, 31, in: newYork), date(2026, 11, 1, in: newYork), date(2026, 11, 2, in: newYork)]
        let summary = calculator.summary(entryDates: dates, now: date(2026, 11, 2, 21, in: newYork))
        #expect(summary.current == 3)
        #expect(summary.longest == 3)
    }

    @Test func springForwardStreak() {
        let calculator = StreakCalculator(calendar: newYork)
        let dates = [date(2026, 3, 7, in: newYork), date(2026, 3, 8, in: newYork), date(2026, 3, 9, in: newYork)]
        #expect(calculator.summary(entryDates: dates, now: date(2026, 3, 9, 22, in: newYork)).current == 3)
    }

    @Test @MainActor func blankAndDeletedEntriesDontCount() {
        let written = JournalEntry(createdAt: date(2026, 11, 11, 9), text: "Hello")
        let blank = JournalEntry(createdAt: date(2026, 11, 10, 9))
        let deleted = JournalEntry(createdAt: date(2026, 11, 10, 10), text: "Gone")
        deleted.deletedAt = date(2026, 11, 11)
        let counted = [written, blank, deleted].countedForStreaks
        #expect(counted == [written.createdAt])
        #expect(calculator.summary(entryDates: counted, now: now).current == 1)
    }
}

// MARK: - Mood statistics

struct MoodStatisticsTests {
    private let week = WeekCalendar(calendar: india).week(containing: date(2026, 11, 11))

    private func stats(_ points: [MoodPoint]) -> MoodStatistics {
        MoodStatistics(points: points, range: week, calendar: india)
    }

    @Test func emptyWeekHasSevenEmptyDays() {
        let stats = stats([])
        #expect(stats.days.count == 7)
        #expect(stats.days.allSatisfy { $0.entryCount == 0 })
        #expect(stats.dominantMood == nil)
        #expect(stats.trend == nil)
        #expect(stats.dayMoodCounts.isEmpty)
    }

    @Test func countsPerDayAndInTotal() {
        let stats = stats([
            MoodPoint(date: date(2026, 11, 9, 9), mood: .calm),
            MoodPoint(date: date(2026, 11, 9, 21), mood: .calm),
            MoodPoint(date: date(2026, 11, 10), mood: .anxious),
            MoodPoint(date: date(2026, 11, 10, 15), mood: nil),
        ])
        #expect(stats.entryCount == 4)
        #expect(stats.untaggedCount == 1)
        #expect(stats.totals == [.calm: 2, .anxious: 1])
        #expect(stats.days[0].counts == [.calm: 2])
        #expect(stats.days[1].counts == [.anxious: 1])
        #expect(stats.days[1].untagged == 1)
        #expect(stats.dayMoodCounts.count == 2)
        #expect(stats.rankedMoods.map(\.mood) == [.calm, .anxious])
    }

    @Test func pointsOutsideRangeAreIgnored() {
        let stats = stats([
            MoodPoint(date: date(2026, 11, 8, 23), mood: .sad),   // Sunday, last week
            MoodPoint(date: date(2026, 11, 16, 0), mood: .sad),   // next Monday 00:00
            MoodPoint(date: date(2026, 11, 12), mood: .joyful),
        ])
        #expect(stats.entryCount == 1)
        #expect(stats.totals == [.joyful: 1])
    }

    @Test func dominantMoodTieGoesToMostRecent() {
        let stats = stats([
            MoodPoint(date: date(2026, 11, 9), mood: .sad),
            MoodPoint(date: date(2026, 11, 10), mood: .calm),
            MoodPoint(date: date(2026, 11, 11), mood: .sad),
            MoodPoint(date: date(2026, 11, 12), mood: .calm),
        ])
        #expect(stats.dominantMood == .calm)
    }

    @Test func lighterTrend() {
        let stats = stats([
            MoodPoint(date: date(2026, 11, 9), mood: .anxious),
            MoodPoint(date: date(2026, 11, 10), mood: .sad),
            MoodPoint(date: date(2026, 11, 14), mood: .calm),
            MoodPoint(date: date(2026, 11, 15), mood: .joyful),
        ])
        #expect(stats.trend == .lighter)
    }

    @Test func heavierTrend() {
        let stats = stats([
            MoodPoint(date: date(2026, 11, 9), mood: .content),
            MoodPoint(date: date(2026, 11, 14), mood: .overwhelmed),
            MoodPoint(date: date(2026, 11, 15), mood: .frustrated),
        ])
        #expect(stats.trend == .heavier)
    }

    @Test func steadyTrend() {
        let stats = stats([
            MoodPoint(date: date(2026, 11, 9), mood: .calm),
            MoodPoint(date: date(2026, 11, 14), mood: .content),
            MoodPoint(date: date(2026, 11, 15), mood: .neutral),
        ])
        #expect(stats.trend == .steady)
    }

    @Test func halfStepChangeIsSteady() {
        // calm (+1) → calm, neutral (avg +0.5): exactly the threshold, not "heavier".
        let stats = stats([
            MoodPoint(date: date(2026, 11, 9), mood: .calm),
            MoodPoint(date: date(2026, 11, 14), mood: .calm),
            MoodPoint(date: date(2026, 11, 15), mood: .neutral),
        ])
        #expect(stats.trend == .steady)
    }

    @Test func noTrendWithTooLittleData() {
        // Only two tagged, or everything in one half.
        #expect(stats([MoodPoint(date: date(2026, 11, 9), mood: .sad),
                       MoodPoint(date: date(2026, 11, 15), mood: .joyful)]).trend == nil)
        #expect(stats([MoodPoint(date: date(2026, 11, 9), mood: .sad),
                       MoodPoint(date: date(2026, 11, 10), mood: .sad),
                       MoodPoint(date: date(2026, 11, 11), mood: .joyful)]).trend == nil)
    }

    @Test func valenceGrouping() {
        #expect(Mood.allCases.filter { $0.valence == .positive } == [.joyful, .content, .calm])
        #expect(Mood.allCases.filter { $0.valence == .neutral } == [.neutral])
        #expect(Mood.allCases.filter { $0.valence == .negative } == [.anxious, .sad, .frustrated, .overwhelmed])
    }

    @Test @MainActor func moodPointsSkipBlankAndDeleted() {
        let tagged = JournalEntry(createdAt: date(2026, 11, 10), text: "Walk")
        tagged.setUserMood(.calm)
        let untagged = JournalEntry(createdAt: date(2026, 11, 11), text: "Notes")
        let deleted = JournalEntry(createdAt: date(2026, 11, 11), text: "Gone")
        deleted.deletedAt = .now
        #expect([tagged, untagged, deleted, JournalEntry()].moodPoints == [
            MoodPoint(date: tagged.createdAt, mood: .calm),
            MoodPoint(date: untagged.createdAt, mood: nil),
        ])
    }
}
