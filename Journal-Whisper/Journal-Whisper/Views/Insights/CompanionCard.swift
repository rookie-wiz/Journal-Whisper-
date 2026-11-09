//
//  CompanionCard.swift
//  Journal-Whisper
//
//  The lantern in Insights, glowing with this week's writing days, and the
//  badge shelf. Unearned badges are shown softly as "not yet", never as missing.
//

import SwiftUI

struct CompanionCard: View {
    let daysThisWeek: Int
    let store: MilestoneStore

    private var brightness: Double { 0.1 + 0.9 * Double(min(daysThisWeek, 7)) / 7 }

    private var message: String {
        switch daysThisWeek {
        case 0: String(localized: "Write today and your lantern will start to glow.")
        case 1: String(localized: "Glowing from 1 day of writing this week.")
        case 7: String(localized: "Glowing brightly: you wrote every day this week.")
        default: String(localized: "Glowing from \(daysThisWeek) days of writing this week.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                LanternView(brightness: brightness, size: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your lantern")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                    Text(message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("lanternMessage")
                }
            }
            .accessibilityElement(children: .combine)

            Text("Badges")
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Milestone.allCases) { milestone in
                    BadgeView(milestone: milestone, earned: store.isEarned(milestone))
                }
            }
            .accessibilityIdentifier("badgeShelf")
        }
        .foregroundStyle(Theme.ink)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companionCard")
    }
}

struct BadgeView: View {
    let milestone: Milestone
    let earned: Bool
    var compact = false
    var showsTitle = true

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(earned ? Theme.glow : Theme.background)
                    .overlay(Circle().strokeBorder(earned ? Theme.outline : Theme.border,
                                                   style: StrokeStyle(lineWidth: 3, dash: earned ? [] : [5, 4])))
                Image(systemName: milestone.symbol)
                    .font(.system(size: compact ? 18 : 20, weight: .bold))
                    .foregroundStyle(earned ? Theme.outline : Theme.inkSecondary.opacity(0.6))
            }
            .frame(width: compact ? 48 : 54, height: compact ? 48 : 54)
            if showsTitle {
                Text(milestone.title)
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .foregroundStyle(earned ? Theme.ink : Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(milestone.title)
        .accessibilityValue(earned ? String(localized: "Earned. \(milestone.detail)") : String(localized: "Not yet. \(milestone.detail)"))
        .accessibilityIdentifier("badge-\(milestone.rawValue)")
    }
}

/// A short, gentle celebration when a badge is earned.
struct BadgeToast: View {
    let milestone: Milestone

    var body: some View {
        HStack(spacing: 12) {
            BadgeView(milestone: milestone, earned: true, compact: true, showsTitle: false)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("New badge · \(milestone.title)")
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.inkSecondary)
                Text(milestone.detail)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.border, lineWidth: 2))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("badgeToast")
    }
}

#Preview {
    VStack {
        CompanionCard(daysThisWeek: 3, store: MilestoneStore(defaults: UserDefaults(suiteName: "preview")!))
        BadgeToast(milestone: .threeDays)
    }
    .padding()
    .background(Theme.background)
}
