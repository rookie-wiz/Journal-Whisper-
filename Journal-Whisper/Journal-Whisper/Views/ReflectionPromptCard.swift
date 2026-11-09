//
//  ReflectionPromptCard.swift
//  Journal-Whisper
//

import SwiftUI

/// Shows reflection prompts (or the support card) in the editor.
struct ReflectionPromptCard: View {
    let state: ReflectionCoordinator.PromptState
    let availability: ReflectionAvailability
    let onUse: (String) -> Void
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Finding a prompt…")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.tint.opacity(0.08), in: .rect(cornerRadius: 14))
            .accessibilityIdentifier("promptsLoading")
        case .ready(let set):
            promptList(set.prompts, note: Self.note(for: set, availability: availability))
        case .support:
            SupportCard()
        }
    }

    private func promptList(_ prompts: [String], note: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Reflect", systemImage: "lightbulb")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Button("New Prompts", systemImage: "arrow.clockwise", action: onRefresh)
                    .labelStyle(.iconOnly)
                Button("Close Prompts", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)

            ForEach(prompts, id: \.self) { prompt in
                Button { onUse(prompt) } label: {
                    Text(prompt)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.background, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Adds this question to your entry")
                .accessibilityIdentifier("reflectionPrompt")
            }

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("promptNote")
            }
        }
        .padding()
        .background(.tint.opacity(0.08), in: .rect(cornerRadius: 14))
    }
}

extension ReflectionPromptCard {
    /// A calm, fixed line explaining general prompts, or nil for personalised ones.
    /// Never the model's own explanation: that's unreviewed text.
    static func note(for set: PromptSet, availability: ReflectionAvailability) -> String? {
        guard set.source == .offline else { return nil }
        // Something the user can act on (Apple Intelligence off, still downloading) comes first.
        if let note = availability.note { return note }
        switch set.fallbackReason {
        case .guardrail?, .refusal?:
            return String(localized: "Personalised prompts aren't available for this entry, so here are some general ones.")
        case .unsupportedLanguage?:
            return String(localized: "Personalised prompts aren't available in this language yet.")
        case .contextTooLong?, .unavailable?, .busy?, .timeout?, .other?:
            return String(localized: "Showing general prompts for now.")
        case nil:
            // Offline by design (e.g. an ineligible device): nothing to explain.
            return nil
        }
    }
}

/// Shown instead of prompts when an entry mentions self-harm, suicide, abuse or
/// danger, with one tap to helplines and emergency numbers.
struct SupportCard: View {
    @State private var showsResources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // fixedSize: this message must never be truncated, even nested in another card.
            Label("You don't have to go through this alone", systemImage: "heart")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("It sounds like things are really hard right now. Talking to someone you trust, or to a crisis line, can help.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("If you're in danger, contact your local emergency number now.")
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showsResources = true
            } label: {
                Label("Get support now", systemImage: "phone.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .accessibilityIdentifier("getSupportNow")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.pink.opacity(0.12), in: .rect(cornerRadius: 14))
        // Contain (not combine) so the button stays its own, tappable element.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("supportCard")
        .sheet(isPresented: $showsResources) {
            NavigationStack {
                CrisisResourcesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsResources = false }
                        }
                    }
            }
        }
    }
}

#Preview("Prompts") {
    ReflectionPromptCard(
        state: .ready(PromptSet(prompts: Array(PromptBank.byMood[.calm]!.prefix(3)), source: .offline, fallbackReason: .guardrail)),
        availability: .available,
        onUse: { _ in }, onRefresh: {}, onDismiss: {}
    )
    .padding()
}

#Preview("Support") {
    ReflectionPromptCard(state: .support, availability: .available,
                         onUse: { _ in }, onRefresh: {}, onDismiss: {})
        .padding()
}
