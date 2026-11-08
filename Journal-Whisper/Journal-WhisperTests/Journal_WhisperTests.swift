//
//  Journal_WhisperTests.swift
//  Journal-WhisperTests
//
//  Created by shubh on 02/11/26.
//

import Testing
@testable import Journal_Whisper

@MainActor
struct JournalEntryTests {

    @Test func blankEntryIsDetected() {
        #expect(JournalEntry().isBlank)
        #expect(JournalEntry(title: "  ", text: "\n\n ").isBlank)
        #expect(!JournalEntry(text: "hello").isBlank)
    }

    @Test func displayTitlePrefersTitle() {
        #expect(JournalEntry(title: "Monday", text: "Body").displayTitle == "Monday")
    }

    @Test func displayTitleFallsBackToFirstLine() {
        #expect(JournalEntry(text: "\n  First line \nSecond").displayTitle == "First line")
        #expect(JournalEntry().displayTitle == "Untitled")
    }

    @Test func previewJoinsLines() {
        #expect(JournalEntry(text: "One\n\n Two ").preview == "One Two")
    }
}

@MainActor
struct MoodTaggingTests {

    @Test func newEntryHasNoMood() {
        let entry = JournalEntry()
        #expect(entry.mood == nil)
        #expect(entry.moodSource == nil)
        #expect(entry.moodIntensity == nil)
    }

    @Test func userMoodIsStored() {
        let entry = JournalEntry()
        entry.setUserMood(.calm, intensity: 4)
        #expect(entry.mood == .calm)
        #expect(entry.moodIntensity == 4)
        #expect(entry.moodSource == .user)
    }

    @Test func intensityIsClamped() {
        let entry = JournalEntry()
        entry.setUserMood(.sad, intensity: 99)
        #expect(entry.moodIntensity == Mood.intensityRange.upperBound)
        entry.applySuggestedMood(.sad, intensity: -3, source: .ai)
        #expect(entry.moodIntensity == Mood.intensityRange.upperBound) // user mood kept
        let other = JournalEntry()
        other.applySuggestedMood(.sad, intensity: -3, source: .ai)
        #expect(other.moodIntensity == Mood.intensityRange.lowerBound)
    }

    @Test func suggestionAppliesWhenNoUserMood() {
        let entry = JournalEntry()
        #expect(entry.applySuggestedMood(.anxious, intensity: 3, source: .ai))
        #expect(entry.mood == .anxious)
        #expect(entry.moodSource == .ai)
        // A newer suggestion may replace an older one.
        #expect(entry.applySuggestedMood(.calm, intensity: 2, source: .heuristic))
        #expect(entry.mood == .calm)
        #expect(entry.moodSource == .heuristic)
    }

    @Test func suggestionNeverOverridesUserMood() {
        let entry = JournalEntry()
        entry.setUserMood(.joyful, intensity: 5)
        #expect(!entry.applySuggestedMood(.sad, intensity: 2, source: .ai))
        #expect(entry.mood == .joyful)
        #expect(entry.moodSource == .user)
    }

    @Test func suggestionCannotClaimUserSource() {
        let entry = JournalEntry()
        #expect(!entry.applySuggestedMood(.sad, intensity: 2, source: .user))
        #expect(entry.mood == nil)
    }

    @Test func clearingAllowsSuggestionsAgain() {
        let entry = JournalEntry()
        entry.setUserMood(.frustrated)
        entry.clearMood()
        #expect(entry.mood == nil)
        #expect(entry.applySuggestedMood(.neutral, intensity: 3, source: .ai))
    }

    @Test func unknownRawValueReadsAsNoMood() {
        let entry = JournalEntry()
        entry.moodRaw = "ecstatic"
        #expect(entry.mood == nil)
    }
}
