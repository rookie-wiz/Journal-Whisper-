//
//  GenerableTypes.swift
//  Journal-Whisper
//
//  Structured output for the on-device model. Guided generation means the model
//  can only answer with these shapes, so there's no free text to parse and no
//  way to return a mood outside the fixed list.
//
//  `GeneratedMood` mirrors `Mood` rather than making `Mood` itself @Generable,
//  so the data model doesn't depend on FoundationModels.
//

import Foundation
import FoundationModels

@Generable
nonisolated enum GeneratedMood: String, CaseIterable {
    case joyful, content, calm, neutral, anxious, sad, frustrated, overwhelmed

    var mood: Mood {
        // Every case has a matching Mood; a unit test guards this.
        Mood(rawValue: rawValue) ?? .neutral
    }
}

@Generable
nonisolated struct MoodAnalysis {
    @Guide(description: "The writer's overall mood by the end of the entry")
    let mood: GeneratedMood

    @Guide(description: "How strongly the writer feels this mood, 1 = faint, 5 = very strong", .range(1...5))
    let intensity: Int
}

@Generable
nonisolated struct ReflectionPromptList {
    @Guide(
        description: "Open-ended, non-judgmental reflection questions, each one sentence under 20 words",
        .count(ReflectionDefaults.promptCount)
    )
    let prompts: [String]
}
