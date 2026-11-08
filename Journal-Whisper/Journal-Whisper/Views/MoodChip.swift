//
//  MoodChip.swift
//  Journal-Whisper
//

import SwiftUI

extension Mood {
    var color: Color {
        switch self {
        case .joyful: .yellow
        case .content: .green
        case .calm: .teal
        case .neutral: .gray
        case .anxious: .orange
        case .sad: .blue
        case .frustrated: .red
        case .overwhelmed: .purple
        }
    }
}

/// A capsule button showing the entry's mood, or an "Add mood" prompt if none is set.
struct MoodChip: View {
    let mood: Mood?
    let source: MoodSource?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let mood {
                    Text(mood.emoji)
                    Text(mood.label)
                    if source == .ai || source == .heuristic {
                        // Mark suggestions so the user knows they can correct them.
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "face.smiling")
                    Text("Add mood")
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background((mood?.color ?? .secondary).opacity(0.15), in: .capsule)
            .foregroundStyle(mood == nil ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("moodChip")
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Choose how you're feeling")
    }

    private var accessibilityText: String {
        guard let mood else { return String(localized: "Add mood") }
        let suggested = (source == .ai || source == .heuristic) ? String(localized: ", suggested") : ""
        return String(localized: "Mood: \(mood.label)") + suggested
    }
}

#Preview {
    VStack(alignment: .leading) {
        MoodChip(mood: nil, source: nil) {}
        MoodChip(mood: .calm, source: .user) {}
        MoodChip(mood: .anxious, source: .ai) {}
    }
    .padding()
}
