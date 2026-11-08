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
        case .ready(let prompts):
            promptList(prompts)
        case .support:
            SupportCard()
        }
    }

    private func promptList(_ prompts: [String]) -> some View {
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

            if let note = availability.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.tint.opacity(0.08), in: .rect(cornerRadius: 14))
    }
}

/// Shown instead of prompts when an entry mentions self-harm, suicide, abuse or danger.
/// Week 4 links this to a full crisis-resources screen.
struct SupportCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("You don't have to go through this alone", systemImage: "heart")
                .font(.subheadline.weight(.semibold))
            Text("It sounds like things are really hard right now. Talking to someone you trust, or to a crisis line, can help.")
                .font(.subheadline)
            Text("If you're in danger, contact your local emergency number now.")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.pink.opacity(0.12), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("supportCard")
    }
}

#Preview("Prompts") {
    ReflectionPromptCard(
        state: .ready(Array(PromptBank.byMood[.calm]!.prefix(3))),
        availability: .appleIntelligenceOff,
        onUse: { _ in }, onRefresh: {}, onDismiss: {}
    )
    .padding()
}

#Preview("Support") {
    ReflectionPromptCard(state: .support, availability: .available,
                         onUse: { _ in }, onRefresh: {}, onDismiss: {})
        .padding()
}
