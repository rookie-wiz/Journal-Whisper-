//
//  StreakCard.swift
//  Journal-Whisper
//
//  Writing streak as stat tiles, not a chart. Worded to encourage: no "you
//  lost your streak", and days-this-week shows progress even after a reset.
//

import SwiftUI

struct StreakCard: View {
    let summary: StreakSummary
    /// The days of the current week, in order.
    let weekDays: [Date]
    let writtenDays: Set<Date>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Writing streak")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(dayCount(summary.current))
                        .font(.system(size: 40, weight: .semibold))
                        .accessibilityIdentifier("currentStreak")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Longest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(dayCount(summary.longest))
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("longestStreak")
                }
            }

            Text(encouragement)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(weekDays, id: \.self) { day in
                        Capsule()
                            .fill(writtenDays.contains(day) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.15)))
                            .frame(height: 8)
                    }
                }
                Text("\(summary.daysThisWeek) of \(weekDays.count) days this week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wrote on \(summary.daysThisWeek) of \(weekDays.count) days this week")
            .accessibilityIdentifier("daysThisWeek")
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func dayCount(_ days: Int) -> String {
        days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
    }

    private var encouragement: String {
        switch (summary.current, summary.wroteToday) {
        case (0, _): String(localized: "Write today to start a new streak.")
        case (_, false): String(localized: "Write today to keep it going.")
        case (1, true): String(localized: "A good start.")
        default: String(localized: "Nice rhythm. Every entry counts.")
        }
    }
}

#Preview {
    let weeks = WeekCalendar()
    let days = weeks.days(in: weeks.week(containing: .now))
    StreakCard(
        summary: StreakSummary(current: 3, longest: 9, wroteToday: false, daysThisWeek: 3),
        weekDays: days,
        writtenDays: Set(days.prefix(3))
    )
    .padding()
}
