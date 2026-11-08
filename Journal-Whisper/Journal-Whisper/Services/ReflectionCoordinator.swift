//
//  ReflectionCoordinator.swift
//  Journal-Whisper
//
//  Decides when mood tagging and prompts run for the entry being edited, and
//  holds the state the editor shows. One per open editor.
//
//  - Mood: runs after the writer pauses (debounced), and once more when the
//    editor closes. Skipped for short entries, unchanged text, and entries
//    whose mood the user chose.
//  - Prompts: only when asked for.
//  - Safety: every edit is checked straight away (cheap, no model), so the
//    support card appears even for a short entry.
//

import Foundation
import Observation
import SwiftData

@Observable
final class ReflectionCoordinator {
    enum PromptState: Equatable {
        case hidden
        case loading
        case ready([String])
        /// Crisis wording detected: show supportive resources instead of prompts.
        case support
    }

    private(set) var promptState: PromptState = .hidden
    private(set) var isAnalyzingMood = false

    private let engine: any ReflectionEngine
    private let debounce: Duration
    private var moodTask: Task<Void, Never>?
    private var promptTask: Task<Void, Never>?

    init(engine: any ReflectionEngine, debounce: Duration = .seconds(3)) {
        self.engine = engine
        self.debounce = debounce
    }

    // MARK: - Mood

    /// Call on every title or text change.
    func entryDidChange(_ entry: JournalEntry) {
        updateSupportState(for: entry)
        moodTask?.cancel()
        guard promptState != .support else { return }
        moodTask = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            await self?.analyzeMoodIfNeeded(entry)
        }
    }

    /// Call when the editor closes: analyse now instead of waiting for the pause.
    /// Returns the task so tests can await it.
    @discardableResult
    func entryWillClose(_ entry: JournalEntry) -> Task<Void, Never> {
        moodTask?.cancel()
        promptTask?.cancel()
        // Holds self strongly so the analysis finishes after the editor is gone.
        return Task { await self.analyzeMoodIfNeeded(entry) }
    }

    func analyzeMoodIfNeeded(_ entry: JournalEntry) async {
        guard !entry.isBlank,
              entry.moodSource != .user,
              entry.needsMoodAnalysis,
              entry.wordCount >= ReflectionDefaults.minimumWordsForMood
        else { return }

        // Captured before the await so edits made during analysis trigger another run.
        let startedAt = Date.now
        let text = entry.reflectionText
        isAnalyzingMood = true
        defer { isAnalyzingMood = false }

        do {
            let result = try await engine.analyzeMood(text)
            // The entry may have been deleted while the model was working.
            guard !Task.isCancelled, entry.modelContext != nil else { return }
            if let result {
                entry.applySuggestedMood(result.mood, intensity: result.intensity, source: result.source)
            }
            entry.moodAnalyzedAt = startedAt
        } catch ReflectionError.needsSupport {
            promptState = .support
        } catch {
            // FallbackEngine already handles model failures; anything else
            // (e.g. cancellation) just leaves the mood as it was.
        }
    }

    // MARK: - Prompts

    func requestPrompts(for entry: JournalEntry) {
        promptTask?.cancel()
        promptState = .loading
        let text = entry.reflectionText, mood = entry.mood
        promptTask = Task { [weak self, engine] in
            do {
                let prompts = try await engine.prompts(for: text, mood: mood)
                guard !Task.isCancelled else { return }
                self?.promptState = .ready(prompts)
            } catch ReflectionError.needsSupport {
                self?.promptState = .support
            } catch is CancellationError {
                return
            } catch {
                // Last resort if the engine stack itself failed.
                guard !Task.isCancelled else { return }
                self?.promptState = .ready(PromptBank.pick(for: mood))
            }
        }
    }

    /// Adds the chosen prompt to the end of the entry as a heading to write under.
    func use(_ prompt: String, in entry: JournalEntry) {
        let existing = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = existing.isEmpty ? "\(prompt)\n" : "\(existing)\n\n\(prompt)\n"
        promptState = .hidden
    }

    func dismissPrompts() {
        promptTask?.cancel()
        if promptState != .support { promptState = .hidden }
    }

    // MARK: - Safety

    private func updateSupportState(for entry: JournalEntry) {
        let needsSupport = SafetyGate.assess(entry.reflectionText) == .needsSupport
        if needsSupport {
            promptTask?.cancel()
            promptState = .support
        } else if promptState == .support {
            promptState = .hidden
        }
    }

    /// Re-check when the editor opens, so a saved entry shows the support card again.
    func entryDidAppear(_ entry: JournalEntry) {
        updateSupportState(for: entry)
        engine.prewarm()
    }
}
