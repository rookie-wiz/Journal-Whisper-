//
//  InsightsView.swift
//  Journal-Whisper
//
//  Streaks and mood patterns, computed on device from the journal. Works with
//  no AI at all; the weekly summary (later step) adds to it.
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(
        filter: #Predicate<JournalEntry> { $0.deletedAt == nil },
        sort: \JournalEntry.createdAt
    ) private var entries: [JournalEntry]

    enum Span: String, CaseIterable, Identifiable {
        case week, month
        var id: Self { self }
        var title: String { self == .week ? String(localized: "Week") : String(localized: "Month") }
        var component: Calendar.Component { self == .week ? .weekOfYear : .month }
    }

    @State private var span: Span = .week
    /// Any date inside the period being shown.
    @State private var anchor: Date = .now
    @State private var showsDailyList = false

    private let calendar = Calendar.current
    private var weeks: WeekCalendar { WeekCalendar(calendar: calendar) }

    private var period: DateInterval {
        span == .week ? weeks.week(containing: anchor) : weeks.month(containing: anchor)
    }
    private var isCurrentPeriod: Bool { period.contains(.now) }

    var body: some View {
        let points = entries.moodPoints
        let stats = MoodStatistics(points: points, range: period, calendar: calendar)
        let streakDates = entries.countedForStreaks
        let thisWeek = weeks.days(in: weeks.week(containing: .now))

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StreakCard(
                    summary: StreakCalculator(calendar: calendar).summary(entryDates: streakDates),
                    weekDays: thisWeek,
                    writtenDays: Set(streakDates.map(weeks.day(of:)))
                )

                Picker("Period", selection: $span) {
                    ForEach(Span.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("insightsSpan")

                periodHeader

                card(title: String(localized: "Moods")) {
                    if stats.entryCount == 0 {
                        emptyNote(span == .week ? String(localized: "No entries this week.") : String(localized: "No entries this month."))
                    } else {
                        switch span {
                        case .week: WeekMoodStrip(stats: stats)
                        case .month: MoodMonthChart(stats: stats)
                        }
                        if let trend = stats.trend {
                            Text(trendText(trend))
                                .font(.subheadline)
                                .accessibilityIdentifier("moodTrend")
                        }
                        if stats.untaggedCount > 0 {
                            Text(stats.untaggedCount == 1
                                 ? String(localized: "1 entry without a mood")
                                 : String(localized: "\(stats.untaggedCount) entries without a mood"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if span == .month {
                            DisclosureGroup("Daily breakdown", isExpanded: $showsDailyList) {
                                DailyMoodList(stats: stats).padding(.top, 6)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                card(title: String(localized: "Most frequent")) {
                    if stats.totals.isEmpty {
                        emptyNote(String(localized: "Add a mood to an entry to see patterns here."))
                    } else {
                        MoodFrequencyChart(stats: stats)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: span) { anchor = .now }
    }

    // MARK: - Pieces

    private var periodHeader: some View {
        HStack {
            Button("Previous", systemImage: "chevron.left") { shift(by: -1) }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("previousPeriod")
            Spacer()
            Text(periodTitle)
                .font(.headline)
                .accessibilityIdentifier("periodTitle")
            Spacer()
            Button("Next", systemImage: "chevron.right") { shift(by: 1) }
                .labelStyle(.iconOnly)
                .disabled(isCurrentPeriod)
                .accessibilityIdentifier("nextPeriod")
        }
        .buttonStyle(.borderless)
    }

    private var periodTitle: String {
        if isCurrentPeriod { return span == .week ? String(localized: "This week") : String(localized: "This month") }
        switch span {
        case .week:
            let lastDay = weeks.previousDay(period.end)
            return "\(period.start.formatted(.dateTime.day().month())) – \(lastDay.formatted(.dateTime.day().month()))"
        case .month:
            return period.start.formatted(.dateTime.month(.wide).year())
        }
    }

    private func shift(by offset: Int) {
        guard let moved = calendar.date(byAdding: span.component, value: offset, to: anchor) else { return }
        anchor = min(moved, .now)
    }

    private func trendText(_ trend: MoodStatistics.Trend) -> String {
        let period = span == .week ? String(localized: "week") : String(localized: "month")
        return switch trend {
        case .lighter: String(localized: "Things felt lighter toward the end of the \(period).")
        case .heavier: String(localized: "The second half of the \(period) felt heavier.")
        case .steady: String(localized: "Your mood was fairly steady this \(period).")
        }
    }

    private func card(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: JournalEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let moods: [Mood?] = [.calm, .anxious, nil, .joyful, .sad, .content, .calm, .frustrated, .overwhelmed, .neutral]
    for (offset, mood) in moods.enumerated() {
        let entry = JournalEntry(createdAt: .now.addingTimeInterval(Double(-offset) * 86_400), text: "Entry \(offset)")
        if let mood { entry.setUserMood(mood) }
        container.mainContext.insert(entry)
    }
    return NavigationStack { InsightsView() }
        .modelContainer(container)
}
