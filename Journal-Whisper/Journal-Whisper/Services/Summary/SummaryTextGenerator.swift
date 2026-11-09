//
//  SummaryTextGenerator.swift
//  Journal-Whisper
//
//  Plain-text generation for weekly summaries, behind a protocol so the
//  step-down logic in ModelSummaryEngine can be tested without the model.
//

import Foundation
import FoundationModels

nonisolated protocol SummaryTextGenerator: Sendable {
    var isAvailable: Bool { get }

    /// Generates plain text. Throws `ReflectionError.generationFailed` on model failures.
    func generate(instructions: String, prompt: String, maxTokens: Int, timeout: Duration) async throws -> String

    /// True if instructions + prompt + `reserve` tokens for the answer fit the context window.
    func fits(instructions: String, prompt: String, reserve: Int) async -> Bool
}

/// The on-device model with permissive guardrails: summarising the user's own
/// writing is a content transformation, the case those guardrails are for.
/// They only apply to plain-text (String) output, which is why summaries
/// aren't @Generable. The model may still answer with a refusal message;
/// ModelSummaryEngine checks for that.
nonisolated struct FoundationModelsTextGenerator: SummaryTextGenerator {
    let model: SystemLanguageModel
    let scheduler: ModelScheduler

    init(
        model: SystemLanguageModel = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations),
        scheduler: ModelScheduler = .shared
    ) {
        self.model = model
        self.scheduler = scheduler
    }

    var isAvailable: Bool { model.isAvailable }

    func generate(instructions: String, prompt: String, maxTokens: Int, timeout: Duration) async throws -> String {
        let model = model
        // The user is looking at Insights, so this goes ahead of background mood work.
        return try await scheduler.run(priority: .userInitiated) {
            try await FoundationModelsEngine.run(timeout: timeout) {
                let session = LanguageModelSession(model: model, instructions: instructions)
                let response = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.5, maximumResponseTokens: maxTokens)
                )
                return response.content
            }
        }
    }

    func fits(instructions: String, prompt: String, reserve: Int) async -> Bool {
        let limit = model.contextSize
        do {
            let used = try await model.tokenCount(for: Instructions(instructions)) + model.tokenCount(for: prompt)
            return used + reserve <= limit
        } catch {
            // Conservative estimate (about 3 characters per token) if counting fails.
            return (instructions.count + prompt.count) / 3 + reserve <= limit
        }
    }
}
