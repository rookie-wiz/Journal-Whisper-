//
//  OnboardingView.swift
//  Journal-Whisper
//
//  Three pages, shown once on first launch: privacy, the on-device helper,
//  and the lantern. Finishing hands over to the lock screen, which asks for
//  Face ID straight away.
//

import SwiftUI

enum Onboarding {
    static let completedKey = "hasCompletedOnboarding"

    /// Shown until completed once. UI tests skip it unless they pass
    /// -showOnboarding, which shows it every launch regardless of the stored flag.
    static func shouldShow(
        completedBefore: Bool,
        finishedThisLaunch: Bool,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if finishedThisLaunch { return false }
        #if DEBUG
        if arguments.contains("-showOnboarding") { return true }
        if arguments.contains("-uiTesting") { return false }
        #endif
        return !completedBefore
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(minHeight: 44)
                    .opacity(page < pageCount - 1 ? 1 : 0)
                    .accessibilityHidden(page == pageCount - 1)
                    .accessibilityIdentifier("onboardingSkip")
            }
            .padding(.horizontal, 24)

            TabView(selection: $page) {
                PrivacyPage().tag(0)
                HelperPage().tag(1)
                LanternPage().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.accent : Theme.border)
                            .frame(width: index == page ? 22 : 10, height: 10)
                    }
                }
                .animation(.spring(duration: 0.3), value: page)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(page + 1) of \(pageCount)")

                Button(page < pageCount - 1 ? "Next" : "Let's go") {
                    if page < pageCount - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                }
                .buttonStyle(.chunky)
                .accessibilityIdentifier("onboardingNext")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .fontDesign(.rounded)
        // A container, so its identifier doesn't overwrite the buttons' identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }
}

// MARK: - Pages

private struct PageLayout<Art: View, Detail: View>: View {
    let title: String
    let message: String
    @ViewBuilder let art: Art
    @ViewBuilder let detail: Detail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                art
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                detail
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct Tile: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.footnote, design: .rounded, weight: .heavy))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(.horizontal, 6)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacyPage: View {
    var body: some View {
        PageLayout(
            title: String(localized: "Your pages stay with you"),
            message: String(localized: "Everything you write stays on this iPhone. No accounts, no servers, no ads.")
        ) {
            HStack(alignment: .bottom, spacing: 12) {
                LanternView(brightness: 0.5, size: 120)
                Text("Hi! I'll keep your pages safe and private.")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .padding(12)
                    .background(Theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4,
                                                                         bottomTrailingRadius: 18, topTrailingRadius: 18))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4,
                                                    bottomTrailingRadius: 18, topTrailingRadius: 18)
                        .strokeBorder(Theme.border, lineWidth: 2))
                    .padding(.bottom, 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } detail: {
            HStack(spacing: 10) {
                Tile(symbol: "person.crop.circle.badge.xmark", text: String(localized: "No account"))
                Tile(symbol: "iphone", text: String(localized: "Stays on this iPhone"))
                Tile(symbol: "faceid", text: String(localized: "Face ID lock"))
            }
        }
    }
}

private struct HelperPage: View {
    var body: some View {
        PageLayout(
            title: String(localized: "A gentle helper, on your iPhone"),
            message: String(localized: "Apple Intelligence on this iPhone can suggest moods, offer questions to reflect on and look back on your week. It never goes online, and you can always change a mood.")
        ) {
            LanternView(brightness: 0.7, size: 140)
                .frame(maxWidth: .infinity)
        } detail: {
            VStack(spacing: 10) {
                Row(symbol: "face.smiling", text: String(localized: "Mood suggestions you can change"))
                Row(symbol: "lightbulb", text: String(localized: "Questions when you want a nudge"))
                Row(symbol: "calendar", text: String(localized: "A short look back at each week"))
            }
            Text("No Apple Intelligence? Everything still works with built-in offline features.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct Row: View {
        let symbol: String
        let text: String
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(text).font(.system(.callout, design: .rounded, weight: .bold))
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 2))
        }
    }
}

private struct LanternPage: View {
    var body: some View {
        PageLayout(
            title: String(localized: "Your lantern grows with you"),
            message: String(localized: "Each day you write, your lantern glows a little brighter. Along the way you'll collect small badges, and they're yours to keep. Missed a day? Nothing is lost.")
        ) {
            HStack(alignment: .bottom, spacing: 4) {
                LanternView(brightness: 0.1, showsFace: false, size: 84)
                LanternView(brightness: 0.5, showsFace: false, size: 104)
                LanternView(brightness: 1, size: 128)
            }
            .frame(maxWidth: .infinity)
        } detail: {
            HStack(spacing: 10) {
                ForEach([Milestone.firstEntry, .threeDays, .sevenDays]) { milestone in
                    BadgeView(milestone: milestone, earned: true, compact: true)
                }
            }
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
