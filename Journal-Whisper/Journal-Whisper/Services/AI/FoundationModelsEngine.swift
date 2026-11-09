//
//  FoundationModelsEngine.swift
//  Journal-Whisper
//
//  Mood tagging and reflection prompts from Apple's on-device language model.
//  Everything runs on device; entry text never leaves the phone.
//
//  Each request uses a fresh LanguageModelSession. Entries are independent, so
//  a long-lived transcript would only fill the context window and carry one
//  entry's content into the next.
//

import Foundation
import FoundationModels
import os

nonisolated struct FoundationModelsEngine: ReflectionEngine {
    /// Tuned for classification and tagging.
    let moodModel: SystemLanguageModel
    /// General model for writing prompts.
    let promptModel: SystemLanguageModel
    /// Serialises model requests app-wide.
    let scheduler: ModelScheduler

    init(
        moodModel: SystemLanguageModel = SystemLanguageModel(useCase: .contentTagging),
        promptModel: SystemLanguageModel = .default,
        scheduler: ModelScheduler = .shared
    ) {
        self.moodModel = moodModel
        self.promptModel = promptModel
        self.scheduler = scheduler
    }

    /// Interactive callers wait at most this long before the offline fallback
    /// takes over. The framework's own timeout is far longer, and a cold model
    /// load can stall the first request for most of a minute.
    static let promptTimeout: Duration = .seconds(15)
    static let moodTimeout: Duration = .seconds(20)

    func analyzeMood(_ text: String) async throws -> MoodResult? {
        try ensureAvailable(moodModel)
        let model = moodModel
        let request = ReflectionInstructions.moodRequest(for: text)
        // Background: a Reflect tap interrupts it; it re-runs later.
        return try await schedule(.background, timeout: Self.moodTimeout) {
            let session = LanguageModelSession(model: model, instructions: ReflectionInstructions.mood)
            let response = try await session.respond(
                to: request,
                generating: MoodAnalysis.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 60)
            )
            return MoodResult(mood: response.content.mood.mood, intensity: response.content.intensity, source: .ai)
        }
    }

    func prompts(for text: String, mood: Mood?) async throws -> PromptSet {
        try ensureAvailable(promptModel)
        let model = promptModel
        let request = ReflectionInstructions.promptsRequest(
            for: text, mood: mood, count: ReflectionDefaults.promptCount)
        let prompts = try await schedule(.userInitiated, timeout: Self.promptTimeout) {
            let session = LanguageModelSession(model: model, instructions: ReflectionInstructions.prompts)
            let response = try await session.respond(
                to: request,
                generating: ReflectionPromptList.self,
                options: GenerationOptions(temperature: 0.8, maximumResponseTokens: 250)
            )
            return response.content.prompts
        }
        return PromptSet(prompts: prompts, source: .ai)
    }

    /// Loads the prompt model (and its instructions) into memory ahead of the first request.
    func prewarm() {
        guard promptModel.isAvailable else { return }
        LanguageModelSession(model: promptModel, instructions: ReflectionInstructions.prompts).prewarm()
    }

    private func ensureAvailable(_ model: SystemLanguageModel) throws {
        guard model.isAvailable else { throw ReflectionError.generationFailed(.unavailable) }
    }

    // MARK: - Scheduling, timeout and errors

    /// Waits for the model, then runs `body` with a time limit. The limit starts
    /// once the model is free, so time spent queued doesn't count against it.
    /// A "busy" answer is retried once after a short pause.
    private func schedule<T: Sendable>(
        _ priority: ModelScheduler.Priority,
        timeout: Duration,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await scheduler.run(priority: priority) {
            do {
                return try await Self.run(timeout: timeout, body)
            } catch ReflectionError.generationFailed(.busy) {
                try await Task.sleep(for: .seconds(1))
                return try await Self.run(timeout: timeout, body)
            }
        }
    }

    /// Runs a model call with a time limit, translating framework errors into
    /// `ReflectionError`. The session is created inside `body` so it never
    /// crosses tasks.
    static func run<T: Sendable>(
        timeout: Duration,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await body() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ReflectionError.generationFailed(.timeout)
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as ReflectionError {
            throw error
        } catch {
            // Interrupted by the scheduler or the caller: the framework may report
            // this as its own error, but it isn't a model failure.
            if Task.isCancelled { throw CancellationError() }
            let failure = failure(for: error)
            if failure == .other {
                // Type and case name only (e.g. "GenerationError.rateLimited"), never the
                // payload or description, which can echo entry text.
                let caseName = Mirror(reflecting: error).children.first?.label ?? "unknown"
                logger.error("Unmapped model error: \(String(reflecting: type(of: error)), privacy: .public).\(caseName, privacy: .public)")
            }
            throw ReflectionError.generationFailed(failure)
        }
    }

    private static let logger = Logger(subsystem: "com.shubh.Journal-Whisper", category: "Reflection")

    static func failure(for error: any Error) -> GenerationFailure {
        switch error {
        case let error as LanguageModelError:
            switch error {
            case .guardrailViolation: .guardrail
            case .refusal: .refusal
            case .contextSizeExceeded: .contextTooLong
            case .unsupportedLanguageOrLocale: .unsupportedLanguage
            case .rateLimited: .busy
            case .timeout: .timeout
            default: .other
            }
        case is SystemLanguageModel.Error:
            // Currently only .assetsUnavailable: the model isn't downloaded or usable.
            .unavailable
        default:
            .other
        }
    }
}
