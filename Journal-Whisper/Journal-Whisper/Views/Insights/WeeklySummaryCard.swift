//
//  WeeklySummaryCard.swift
//  Journal-Whisper
//

import SwiftUI

struct WeeklySummaryCard: View {
    let state: WeeklySummaryCoordinator.State
    let needsSupport: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week in review").font(.headline)

            switch state {
            case .idle, .empty:
                Text("Write this week to see a summary here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking back on your week…").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityIdentifier("summaryLoading")
            case .ready(let draft, let entryCount, _):
                Text(draft.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("summaryText")

                if let question = draft.closingQuestion {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("For the week ahead")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(question)
                            .font(.subheadline)
                            .accessibilityIdentifier("summaryQuestion")
                    }
                }

                Text(Self.footer(draft: draft, entryCount: entryCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("summaryFooter")
            }

            if needsSupport {
                SupportCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        // A container, so its identifier doesn't overwrite the children's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weeklySummaryCard")
    }

    /// Says what the summary is based on. For the offline template, says so
    /// calmly, and why when the model declined; never the model's own words.
    static func footer(draft: SummaryDraft, entryCount: Int) -> String {
        let based = entryCount == 1
            ? String(localized: "Based on 1 entry")
            : String(localized: "Based on \(entryCount) entries")
        guard draft.source == .offline else { return based }
        switch draft.fallbackReason {
        case .guardrail?, .refusal?:
            return based + String(localized: " · a written summary wasn't available for this week, so this one comes from your moods")
        case .unavailable?, .busy?, .timeout?, .other?, .contextTooLong?, .unsupportedLanguage?:
            return based + String(localized: " · from your moods and writing days for now")
        case nil:
            return based + String(localized: " · from your moods and writing days")
        }
    }
}

#Preview {
    VStack {
        WeeklySummaryCard(
            state: .ready(
                SummaryDraft(text: "You wrote on 4 days this week. Calm came up most often. Things felt lighter toward the end of the week.",
                             source: .offline, closingQuestion: "What helped you feel at ease today?"),
                entryCount: 5, generatedAt: .now),
            needsSupport: false
        )
        WeeklySummaryCard(state: .loading, needsSupport: false)
    }
    .padding()
}
