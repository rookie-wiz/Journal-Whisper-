//
//  ThemeAndMilestoneTests.swift
//  Journal-WhisperTests
//
//  Badges (earned once, never lost), onboarding visibility, and theme contrast.
//

import Foundation
import Testing
import SwiftData
import UIKit
import SwiftUI
@testable import Journal_Whisper

struct MilestoneTests {

    private func store() -> MilestoneStore {
        MilestoneStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    @Test func thresholds() {
        let none = Milestone.Progress(entryCount: 0, longestStreak: 0, hasMood: false)
        #expect(Milestone.allCases.allSatisfy { !$0.isReached(by: none) })
        let some = Milestone.Progress(entryCount: 10, longestStreak: 3, hasMood: true)
        #expect(Set(Milestone.allCases.filter { $0.isReached(by: some) })
                == [.firstEntry, .namedAFeeling, .threeDays, .tenEntries])
        let lots = Milestone.Progress(entryCount: 30, longestStreak: 7, hasMood: true)
        #expect(Milestone.allCases.allSatisfy { $0.isReached(by: lots) })
    }

    @Test func earnedOnceAndCelebrated() {
        let store = store()
        let new = store.update(with: .init(entryCount: 1, longestStreak: 1, hasMood: false))
        #expect(new == [.firstEntry])
        #expect(store.justEarned == .firstEntry)
        // Nothing new: no repeat celebration.
        store.justEarned = nil
        #expect(store.update(with: .init(entryCount: 2, longestStreak: 1, hasMood: false)).isEmpty)
        #expect(store.justEarned == nil)
    }

    @Test func neverLostWhenProgressDrops() {
        let store = store()
        store.update(with: .init(entryCount: 12, longestStreak: 4, hasMood: true))
        // Entries deleted, streak broken:
        store.update(with: .init(entryCount: 0, longestStreak: 0, hasMood: false))
        #expect(store.isEarned(.tenEntries))
        #expect(store.isEarned(.threeDays))
    }

    @Test func persistsAcrossLaunchesAndResets() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        MilestoneStore(defaults: defaults).update(with: .init(entryCount: 1, longestStreak: 1, hasMood: true))
        let reopened = MilestoneStore(defaults: defaults)
        #expect(reopened.isEarned(.firstEntry) && reopened.isEarned(.namedAFeeling))
        reopened.reset()
        #expect(MilestoneStore(defaults: defaults).earned.isEmpty)
    }

    @Test @MainActor func progressFromEntries() {
        let a = JournalEntry(createdAt: .now, text: "Today")
        a.setUserMood(.calm)
        let blank = JournalEntry(createdAt: .now)
        let deleted = JournalEntry(createdAt: .now.addingTimeInterval(-86_400), text: "Gone")
        deleted.deletedAt = .now
        let progress = [a, blank, deleted].milestoneProgress
        #expect(progress == .init(entryCount: 1, longestStreak: 1, hasMood: true))
    }
}

struct OnboardingTests {
    @Test func visibility() {
        // Real launches.
        #expect(Onboarding.shouldShow(completedBefore: false, finishedThisLaunch: false, arguments: []))
        #expect(!Onboarding.shouldShow(completedBefore: true, finishedThisLaunch: false, arguments: []))
        #expect(!Onboarding.shouldShow(completedBefore: false, finishedThisLaunch: true, arguments: []))
        // UI tests: skipped unless asked for, and then shown regardless of the stored flag.
        #expect(!Onboarding.shouldShow(completedBefore: false, finishedThisLaunch: false, arguments: ["-uiTesting"]))
        #expect(Onboarding.shouldShow(completedBefore: true, finishedThisLaunch: false, arguments: ["-uiTesting", "-showOnboarding"]))
        #expect(!Onboarding.shouldShow(completedBefore: true, finishedThisLaunch: true, arguments: ["-uiTesting", "-showOnboarding"]))
    }
}

struct ThemeContrastTests {
    /// WCAG relative-luminance contrast between two colours in one appearance.
    private func contrast(_ a: Color, _ b: Color, dark: Bool) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        func luminance(_ color: Color) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &bl, alpha: &alpha)
            func channel(_ c: CGFloat) -> Double {
                let c = Double(c)
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(bl)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test(arguments: [false, true])
    func textPairsMeetAA(dark: Bool) {
        for (fg, bg, name) in [
            (Theme.ink, Theme.background, "ink on background"),
            (Theme.inkSecondary, Theme.background, "secondary on background"),
            (Theme.ink, Theme.surface, "ink on surface"),
            (Theme.inkSecondary, Theme.surface, "secondary on surface"),
            (Theme.accent, Theme.background, "tint on background"),
            (Theme.accent, Theme.surface, "tint on surface"),
            (Color.white, Theme.buttonFill, "button text"),
        ] {
            #expect(contrast(fg, bg, dark: dark) >= 4.5, "\(name) in \(dark ? "dark" : "light"): \(contrast(fg, bg, dark: dark))")
        }
    }
}
