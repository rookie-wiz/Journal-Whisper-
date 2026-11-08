//
//  PromptBank.swift
//  Journal-Whisper
//
//  Hand-written reflection prompts used when the on-device model is unavailable,
//  fails, or there's no text to work from yet. Every prompt is an open question,
//  non-judgmental, under 20 words, and gives no advice.
//

import Foundation

nonisolated enum PromptBank {
    /// Prompts that suit any entry, including a blank one.
    static let general: [String] = [
        "What's taking up the most space in your mind right now?",
        "What was the best part of your day, even if it was small?",
        "What's something you noticed today that you'd usually overlook?",
        "Who did you think about today, and why?",
        "What would you like to remember about today a year from now?",
        "What's one thing you're looking forward to?",
        "If today had a title, what would it be?",
        "What did you learn about yourself this week?",
    ]

    static let byMood: [Mood: [String]] = [
        .joyful: [
            "What made today feel so good?",
            "Who would you like to share this feeling with?",
            "What helped this moment happen, and could it happen again?",
            "How does this joy feel in your body?",
            "What do you want to hold on to from today?",
        ],
        .content: [
            "What are you quietly grateful for right now?",
            "What's going well that you haven't stopped to notice?",
            "What small thing made today feel steady?",
            "What does a good, ordinary day look like for you?",
            "Who or what helped you feel settled today?",
        ],
        .calm: [
            "What helped you feel at ease today?",
            "Where were you when you felt most peaceful?",
            "What would you like to bring more of into your week?",
            "What did you have space to think about today?",
            "How did you look after yourself today?",
        ],
        .neutral: [
            "What's one moment from today that stood out, even a little?",
            "What would have made today feel more like yours?",
            "What's been on autopilot lately?",
            "What are you curious about right now?",
            "What's one thing you'd like to change about tomorrow?",
        ],
        .anxious: [
            "What's worrying you most, and what part of it can you control?",
            "What would you tell a friend who felt this way?",
            "What's helped you through a worry like this before?",
            "What's one small thing that feels manageable right now?",
            "What would feeling a little safer look like today?",
        ],
        .sad: [
            "What do you need most right now?",
            "Who or what has comforted you before when you felt like this?",
            "What would you like someone to understand about how you feel?",
            "What's one kind thing you could do for yourself today?",
            "What's weighing on you, if you want to put it into words?",
        ],
        .frustrated: [
            "What happened that didn't feel fair or right?",
            "What did you need in that moment that you didn't get?",
            "What part of this is in your hands, and what isn't?",
            "How would you like to feel about this a week from now?",
            "What would you say if you could say anything?",
        ],
        .overwhelmed: [
            "If you could set one thing down today, what would it be?",
            "What's the very next small step, and only that?",
            "Who could you ask for a little help?",
            "What can wait until tomorrow?",
            "What would make the next hour a bit easier?",
        ],
    ]

    /// Picks `count` distinct prompts: mostly mood-specific, topped up with general ones.
    static func pick(
        for mood: Mood?,
        count: Int = ReflectionDefaults.promptCount,
        using rng: inout some RandomNumberGenerator
    ) -> [String] {
        guard count > 0 else { return [] }
        let moodPrompts = mood.flatMap { byMood[$0] } ?? []
        // Leave one slot for a general prompt when there are mood prompts, for variety.
        let moodSlots = moodPrompts.isEmpty ? 0 : min(moodPrompts.count, max(count - 1, 1))
        var picked = Array(moodPrompts.shuffled(using: &rng).prefix(moodSlots))
        picked += general.shuffled(using: &rng).prefix(count - picked.count)
        return picked
    }

    static func pick(for mood: Mood?, count: Int = ReflectionDefaults.promptCount) -> [String] {
        var rng = SystemRandomNumberGenerator()
        return pick(for: mood, count: count, using: &rng)
    }
}
