//
//  HeuristicEngineTests.swift
//  Journal-WhisperTests
//

import Testing
@testable import Journal_Whisper

struct HeuristicClassifierTests {

    @Test(arguments: [
        ("Got the internship! I'm so happy and excited.", Mood.joyful),
        ("Quiet evening. Grateful for a good day with family.", .content),
        ("Long walk by the lake, felt peaceful and relaxed.", .calm),
        ("Nothing much happened, a pretty ordinary day.", .neutral),
        ("Exams tomorrow and I'm really nervous and worried.", .anxious),
        ("I cried after the call. Feeling down and lonely.", .sad),
        ("The group project is so frustrating, I'm fed up.", .frustrated),
        ("Three deadlines, too much to do, completely swamped.", .overwhelmed),
    ])
    func classifiesClearEntries(text: String, expected: Mood) throws {
        let result = try #require(HeuristicEngine.classify(text))
        #expect(result.mood == expected)
        #expect(result.source == .heuristic)
    }

    @Test func returnsNilWithoutSignal() {
        #expect(HeuristicEngine.classify("") == nil)
        #expect(HeuristicEngine.classify("Went to the library and then the shop.") == nil)
    }

    @Test func ignoresNegatedWords() {
        #expect(HeuristicEngine.classify("I'm not happy about it.") == nil)
        #expect(HeuristicEngine.classify("Wasn't really stressed today.") == nil)
    }

    @Test func negationDoesNotCrossPunctuation() {
        // Found by the offline mood evaluation.
        #expect(HeuristicEngine.classify("No rush, no plans. Very at ease.")?.mood == .calm)
        #expect(HeuristicEngine.classify("I wasn't invited. Feeling lonely and a bit down.")?.mood == .sad)
        #expect(HeuristicEngine.classify("Not tired, just happy.")?.mood == .joyful)
        // Negation within the same clause still applies.
        #expect(HeuristicEngine.classify("I am not at ease.") == nil)
    }

    @Test func ambiguousWordsOnlyCountInPhrases() {
        #expect(HeuristicEngine.classify("I sat down and missed the bus.") == nil)
        #expect(HeuristicEngine.classify("Feeling down tonight.")?.mood == .sad)
    }

    @Test func handlesCaseAndCurlyApostrophes() {
        #expect(HeuristicEngine.classify("I CAN’T COPE with this week")?.mood == .overwhelmed)
    }

    @Test func mostHitsWins() {
        let text = "A bit happy this morning, but anxious, nervous and worried all afternoon."
        #expect(HeuristicEngine.classify(text)?.mood == .anxious)
    }

    @Test func tieGoesToLatestMention() {
        #expect(HeuristicEngine.classify("Stressed at work, then calm at home.")?.mood == .calm)
        #expect(HeuristicEngine.classify("Calm at home, then stressed at work.")?.mood == .anxious)
    }

    @Test func intensityGrowsWithEvidence() throws {
        let mild = try #require(HeuristicEngine.classify("Felt a little sad."))
        let strong = try #require(HeuristicEngine.classify("So sad. Cried, upset, heartbroken, hopeless."))
        #expect(mild.intensity == 2)
        #expect(strong.intensity == 5)
        #expect(Mood.intensityRange.contains(strong.intensity))
    }

    @Test func intensifierRaisesIntensity() throws {
        let plain = try #require(HeuristicEngine.classify("I am tired and anxious."))
        let boosted = try #require(HeuristicEngine.classify("I am tired and very anxious."))
        #expect(boosted.intensity == plain.intensity + 1)
    }

    @Test func everyLexiconPhraseIsReachable() {
        // Guards against typos like a capital letter or punctuation in the word list.
        for (mood, phrases) in MoodLexicon.phrases {
            for phrase in phrases {
                let text = phrase.joined(separator: " ")
                #expect(HeuristicEngine.classify(text)?.mood == mood, "\"\(text)\" should be \(mood)")
            }
        }
    }
}

struct PromptBankTests {

    @Test func everyMoodHasEnoughPrompts() {
        for mood in Mood.allCases {
            #expect((PromptBank.byMood[mood]?.count ?? 0) >= ReflectionDefaults.promptCount, "\(mood)")
        }
    }

    @Test func promptsAreShortQuestions() {
        let all = PromptBank.general + PromptBank.byMood.values.flatMap { $0 }
        for prompt in all {
            #expect(prompt.hasSuffix("?"), "\(prompt)")
            #expect(prompt.split(separator: " ").count <= 20, "\(prompt)")
        }
        #expect(Set(all).count == all.count, "Prompts should be unique")
    }

    @Test func pickMixesMoodAndGeneralPrompts() {
        var rng = SeededGenerator(seed: 42)
        let picked = PromptBank.pick(for: .anxious, using: &rng)
        #expect(picked.count == ReflectionDefaults.promptCount)
        #expect(Set(picked).count == picked.count)
        let moodPrompts = Set(PromptBank.byMood[.anxious]!)
        #expect(picked.filter(moodPrompts.contains).count == ReflectionDefaults.promptCount - 1)
        #expect(picked.filter(PromptBank.general.contains).count == 1)
    }

    @Test func pickWithoutMoodUsesGeneralPrompts() {
        var rng = SeededGenerator(seed: 7)
        let picked = PromptBank.pick(for: nil, using: &rng)
        #expect(picked.count == ReflectionDefaults.promptCount)
        #expect(picked.allSatisfy(PromptBank.general.contains))
    }

    @Test func pickIsDeterministicForASeed() {
        var a = SeededGenerator(seed: 1), b = SeededGenerator(seed: 1)
        #expect(PromptBank.pick(for: .sad, using: &a) == PromptBank.pick(for: .sad, using: &b))
    }

    @Test func pickHandlesEdgeCounts() {
        var rng = SeededGenerator(seed: 3)
        #expect(PromptBank.pick(for: .calm, count: 0, using: &rng).isEmpty)
        #expect(PromptBank.pick(for: .calm, count: 1, using: &rng).count == 1)
    }
}

struct HeuristicEngineTests {

    @Test func analyzeMoodMatchesClassifier() async throws {
        let result = try await HeuristicEngine().analyzeMood("Really nervous about tomorrow.")
        #expect(result?.mood == .anxious)
    }

    @Test func promptsUseGivenMood() async throws {
        let prompts = try await HeuristicEngine().prompts(for: "", mood: .overwhelmed)
        let overwhelmed = Set(PromptBank.byMood[.overwhelmed]!)
        #expect(prompts.contains(where: overwhelmed.contains))
    }

    @Test func promptsInferMoodFromTextWhenMissing() async throws {
        let prompts = try await HeuristicEngine().prompts(for: "So frustrated and annoyed.", mood: nil)
        let frustrated = Set(PromptBank.byMood[.frustrated]!)
        #expect(prompts.contains(where: frustrated.contains))
    }

    @Test func blankEntryGetsGeneralPrompts() async throws {
        let prompts = try await HeuristicEngine().prompts(for: "  ", mood: nil)
        #expect(prompts.count == ReflectionDefaults.promptCount)
        #expect(prompts.allSatisfy(PromptBank.general.contains))
    }
}

/// SplitMix64: a tiny deterministic generator for repeatable shuffles in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
