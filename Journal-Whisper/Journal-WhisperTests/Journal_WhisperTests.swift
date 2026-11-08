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
