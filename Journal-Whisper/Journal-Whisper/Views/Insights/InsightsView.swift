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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.summaryEngine) private var summaryEngine
    @Environment(MilestoneStore.self) private var milestones
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
    /// Created on appear, once the environment's engine is available.
    @State private var summary: WeeklySummaryCoordinator?

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
                let streak = StreakCalculator(calendar: calendar).summary(entryDates: streakDates)
                CompanionCard(daysThisWeek: streak.daysThisWeek, store: milestones)
                StreakCard(
                    summary: streak,
                    weekDays: thisWeek,
                    writtenDays: Set(streakDates.map(weeks.day(of:)))
                )

                Picker("Period", selection: $span) {
                    ForEach(Span.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("insightsSpan")

                periodHeader

                if span == .week, let summary {
                    WeeklySummaryCard(state: summary.state, needsSupport: summary.needsSupport)
                }

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
        .foregroundStyle(Theme.ink)
        .fontDesign(.rounded)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: span) { anchor = .now }
        .onAppear {
            if summary == nil { summary = WeeklySummaryCoordinator(engine: summaryEngine) }
        }
        // Re-checks whenever the week or anything in it changes; reuses the
        // saved summary when it still matches.
        .task(id: summaryKey) {
            guard span == .week else { return }
            if summary == nil { summary = WeeklySummaryCoordinator(engine: summaryEngine) }
            summary?.refresh(week: period, entries: entries, context: modelContext, calendar: calendar)
        }
    }

    private var summaryKey: String {
        guard span == .week else { return "month" }
        return WeekSnapshot(week: period, journal: entries, calendar: calendar).fingerprint
            + "\(period.start.timeIntervalSinceReferenceDate)"
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
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 2))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let container = try! ModelContainer.journal(inMemory: true)
    let moods: [Mood?] = [.calm, .anxious, nil, .joyful, .sad, .content, .calm, .frustrated, .overwhelmed, .neutral]
    for (offset, mood) in moods.enumerated() {
        let entry = JournalEntry(createdAt: .now.addingTimeInterval(Double(-offset) * 86_400), text: "Entry \(offset)")
        if let mood { entry.setUserMood(mood) }
        container.mainContext.insert(entry)
    }
    return NavigationStack { InsightsView() }
        .environment(MilestoneStore())
        .modelContainer(container)
}
