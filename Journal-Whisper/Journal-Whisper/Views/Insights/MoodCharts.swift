//
//  MoodCharts.swift
//  Journal-Whisper
//
//  Mood visuals for a week or month:
//  - Week: a strip of seven days showing each entry's emoji. With one or two
//    entries a day, emoji say more than stacked colour.
//  - Month: stacked bars per day, coloured by mood in the validated
//    `Mood.chartOrder`, with a legend and tap-to-inspect.
//  - Frequency: ranked horizontal bars in a single hue (comparing parts
//    doesn't need eight colours).
//  Identity never depends on colour alone: every mood is named with its emoji.
//

import SwiftUI
import Charts

// MARK: - Week strip

struct WeekMoodStrip: View {
    let stats: MoodStatistics
    private static let maxShown = 3

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(stats.days) { day in
                VStack(spacing: 6) {
                    Text(day.day, format: .dateTime.weekday(.narrow))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(day.day, format: .dateTime.day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    moods(for: day)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(day.day, format: .dateTime.weekday(.wide).day().month()))
                .accessibilityValue(description(of: day))
            }
        }
        .accessibilityIdentifier("weekMoodStrip")
    }

    @ViewBuilder
    private func moods(for day: MoodStatistics.Day) -> some View {
        let emoji = Mood.chartOrder.flatMap { mood in
            Array(repeating: mood.emoji, count: day.counts[mood] ?? 0)
        }
        VStack(spacing: 2) {
            if day.entryCount == 0 {
                Circle().fill(.quaternary).frame(width: 6, height: 6).padding(.top, 6)
            } else {
                ForEach(Array(emoji.prefix(Self.maxShown).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.title3)
                }
                let hidden = max(0, emoji.count - Self.maxShown)
                if hidden > 0 {
                    Text("+\(hidden)").font(.caption2).foregroundStyle(.secondary)
                }
                if day.untagged > 0 {
                    // Entries written without a mood.
                    Image(systemName: "square.and.pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func description(of day: MoodStatistics.Day) -> String {
        guard day.entryCount > 0 else { return String(localized: "No entries") }
        var parts = Mood.chartOrder.compactMap { mood in
            day.counts[mood].map { $0 == 1 ? mood.label : "\(mood.label) ×\($0)" }
        }
        if day.untagged > 0 { parts.append(String(localized: "\(day.untagged) without a mood")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Month chart

struct MoodMonthChart: View {
    let stats: MoodStatistics
    @State private var selectedDay: Date?

    /// Segments with explicit start and end, stacked in `Mood.chartOrder`.
    private struct Segment: Identifiable {
        let day: Date
        let mood: Mood
        let start: Int
        let end: Int
        var id: String { "\(day.timeIntervalSinceReferenceDate)-\(mood.rawValue)" }
    }

    private var segments: [Segment] {
        stats.days.flatMap { day in
            var running = 0
            return Mood.chartOrder.compactMap { mood -> Segment? in
                guard let count = day.counts[mood] else { return nil }
                defer { running += count }
                return Segment(day: day.day, mood: mood, start: running, end: running + count)
            }
        }
    }

    /// Weekly ticks, skipping one too close to the end to fit (it clipped at the edge).
    private var axisDates: [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var date = stats.range.start
        let lastFitting = stats.range.end.addingTimeInterval(-4 * 86_400)
        while date <= lastFitting {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 7, to: date) else { break }
            date = next
        }
        return dates
    }

    /// Only moods that appear get a legend entry; each keeps its own colour.
    private var presentMoods: [Mood] { Mood.chartOrder.filter { stats.totals[$0] != nil } }

    private var selected: MoodStatistics.Day? {
        guard let selectedDay else { return nil }
        let day = Calendar.current.startOfDay(for: selectedDay)
        return stats.days.first { $0.day == day }
    }

    var body: some View {
        Chart {
            ForEach(segments) { segment in
                BarMark(
                    x: .value("Day", segment.day, unit: .day),
                    yStart: .value("Entries", segment.start),
                    yEnd: .value("Entries", segment.end),
                    width: .ratio(0.7)
                )
                .foregroundStyle(by: .value("Mood", segment.mood.chartLabel))
                // A 1pt inset on every side leaves a 2pt surface gap between stacked segments.
                .clipShape(RoundedRectangle(cornerRadius: 3).inset(by: 1))
                .accessibilityLabel(Text(segment.day, format: .dateTime.weekday(.wide).day().month()))
                .accessibilityValue("\(segment.mood.label), \(segment.end - segment.start)")
            }
            if let selected {
                RuleMark(x: .value("Day", selected.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        DayPopover(day: selected)
                    }
            }
        }
        .chartForegroundStyleScale(domain: presentMoods.map(\.chartLabel), range: presentMoods.map(\.color))
        // Our own legend below wraps cleanly; the built-in one clipped at the edge.
        .chartLegend(.hidden)
        // The whole month, so days still to come read as empty, not missing.
        .chartXScale(domain: stats.range.start...stats.range.end)
        .chartXSelection(value: $selectedDay)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: axisDates) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 200)
        .accessibilityIdentifier("moodMonthChart")

        MoodLegend(moods: presentMoods)
    }
}

/// Swatch + emoji + name in two columns. Text stays in text colours; the swatch carries the hue.
struct MoodLegend: View {
    let moods: [Mood]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(moods) { mood in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(mood.color)
                        .frame(width: 10, height: 10)
                    Text(mood.chartLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("moodLegend")
    }
}

private struct DayPopover: View {
    let day: MoodStatistics.Day

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.day, format: .dateTime.weekday(.abbreviated).day().month())
                .font(.caption.weight(.semibold))
            if day.entryCount == 0 {
                Text("No entries").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Mood.chartOrder.filter { day.counts[$0] != nil }) { mood in
                Text("\(mood.chartLabel)  \(day.counts[mood]!)").font(.caption)
            }
            if day.untagged > 0 {
                Text("\(day.untagged) without a mood").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
    }
}

// MARK: - Frequency

struct MoodFrequencyChart: View {
    let stats: MoodStatistics

    var body: some View {
        let ranked = stats.rankedMoods
        let top = Double(ranked.first?.count ?? 1)
        // Rows rather than a Chart axis: labels get their own column and can't
        // overlap the bars. One hue throughout; the label carries identity.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ranked, id: \.mood) { item in
                HStack(spacing: 10) {
                    Text(item.mood.chartLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(width: 130, alignment: .leading)
                    GeometryReader { proxy in
                        UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                            .fill(.tint)
                            .frame(width: max(4, proxy.size.width * Double(item.count) / top), height: 16)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 20)
                    Text("\(item.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 16, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.mood.label)
                .accessibilityValue(item.count == 1 ? "1 entry" : "\(item.count) entries")
            }
        }
        .accessibilityIdentifier("moodFrequencyChart")
    }
}

/// A plain list of every day with entries: the table view behind the month chart.
struct DailyMoodList: View {
    let stats: MoodStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(stats.days.filter { $0.entryCount > 0 }) { day in
                HStack(alignment: .firstTextBaseline) {
                    Text(day.day, format: .dateTime.weekday(.abbreviated).day().month())
                        .font(.subheadline)
                        .frame(width: 110, alignment: .leading)
                    Text(summary(of: day))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func summary(of day: MoodStatistics.Day) -> String {
        var parts = Mood.chartOrder.compactMap { mood in
            day.counts[mood].map { $0 == 1 ? mood.chartLabel : "\(mood.chartLabel) ×\($0)" }
        }
        if day.untagged > 0 { parts.append(String(localized: "\(day.untagged) without a mood")) }
        return parts.joined(separator: ", ")
    }
}
