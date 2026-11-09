//
//  WeekCalendar.swift
//  Journal-Whisper
//
//  Day and week boundaries for insights. Weeks follow the user's locale
//  (Monday-first in India, Sunday-first in the US), and all arithmetic goes
//  through Calendar so daylight-saving days (23 or 25 hours) stay correct.
//

import Foundation

nonisolated struct WeekCalendar: Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Midnight at the start of the date's day.
    func day(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func week(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: day(of: date), duration: 7 * 86_400)
    }

    func month(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: day(of: date), duration: 30 * 86_400)
    }

    /// The week before or after (`offset` -1 or +1, or further).
    func week(offsetBy offset: Int, from week: DateInterval) -> DateInterval {
        let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: week.start) ?? week.start
        return self.week(containing: shifted)
    }

    /// The start of each day in the interval, in order.
    func days(in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var current = day(of: interval.start)
        while current < interval.end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    /// The day before.
    func previousDay(_ day: Date) -> Date {
        calendar.date(byAdding: .day, value: -1, to: day).map(calendar.startOfDay) ?? day
    }

    /// True if `later` is the calendar day right after `earlier` (both day starts).
    func isDay(_ later: Date, rightAfter earlier: Date) -> Bool {
        calendar.dateComponents([.day], from: earlier, to: later).day == 1
    }
}
