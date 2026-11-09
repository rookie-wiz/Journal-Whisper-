//
//  MoodChip.swift
//  Journal-Whisper
//

import SwiftUI
import UIKit

extension Mood {
    /// Each mood keeps a hue that suits it (sad blue, frustrated red, joyful
    /// yellow…), drawn from a categorical palette validated for colour-vision
    /// deficiency, with separate light and dark steps.
    var color: Color {
        switch self {
        case .sad: Self.dynamic(light: 0x2a78d6, dark: 0x3987e5)          // blue
        case .anxious: Self.dynamic(light: 0xeb6834, dark: 0xd95926)      // orange
        case .calm: Self.dynamic(light: 0x1baf7a, dark: 0x199e70)         // aqua
        case .joyful: Self.dynamic(light: 0xeda100, dark: 0xc98500)       // yellow
        case .neutral: Self.dynamic(light: 0xe87ba4, dark: 0xd55181)      // magenta
        case .content: Self.dynamic(light: 0x008300, dark: 0x008300)      // green
        case .overwhelmed: Self.dynamic(light: 0x6250d6, dark: 0x9085e9)  // violet
        case .frustrated: Self.dynamic(light: 0xe34948, dark: 0xe66767)   // red
        }
    }

    /// Stacking order for charts. It's the palette's validated order, so every
    /// pair of neighbouring segments stays distinguishable under colour-vision
    /// deficiency. (Ordering by valence instead failed the check: magenta beside
    /// red or orange, and aqua beside magenta in dark mode, were too close.)
    static let chartOrder: [Mood] = [.sad, .anxious, .calm, .joyful, .neutral, .content, .overwhelmed, .frustrated]

    /// Emoji and name, for chart labels and legends (identity never relies on colour alone).
    var chartLabel: String { "\(emoji) \(label)" }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: 1
            )
        })
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
