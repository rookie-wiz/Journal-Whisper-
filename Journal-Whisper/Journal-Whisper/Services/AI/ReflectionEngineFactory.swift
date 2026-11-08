//
//  ReflectionEngineFactory.swift
//  Journal-Whisper
//
//  Builds the engine stack the app uses:
//
//      SafeguardedEngine            crisis check before, prompt filter after
//        └─ FallbackEngine          any model failure → offline engine
//             ├─ FoundationModelsEngine   on-device model
//             └─ HeuristicEngine          keywords + prompt bank
//
//  To try a different model provider, replace `FoundationModelsEngine()` below.
//

import SwiftUI
import FoundationModels

nonisolated enum ReflectionEngineFactory {
    static func makeDefault() -> any ReflectionEngine {
        SafeguardedEngine(FallbackEngine(primary: FoundationModelsEngine(), fallback: HeuristicEngine()))
    }

    /// Offline only; no model calls.
    static func makeOffline() -> any ReflectionEngine {
        SafeguardedEngine(HeuristicEngine())
    }
}

/// Whether AI features are on, and if not, what the user can do about it.
/// Reads `SystemLanguageModel`, which is Observable, so views update when the
/// model finishes downloading or Apple Intelligence is turned on.
enum ReflectionAvailability: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceOff
    case modelNotReady
    case unsupportedLanguage

    static var current: ReflectionAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale() ? .available : .unsupportedLanguage
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceOff
        case .unavailable(.modelNotReady): return .modelNotReady
        case .unavailable: return .deviceNotEligible
        }
    }

    /// A short note for the UI when suggestions come from the offline fallback, or nil.
    var note: String? {
        switch self {
        case .available, .deviceNotEligible:
            // Nothing the user can change on an ineligible device, so stay quiet.
            nil
        case .appleIntelligenceOff:
            String(localized: "Turn on Apple Intelligence in Settings for prompts based on what you write.")
        case .modelNotReady:
            String(localized: "Apple Intelligence is still getting ready. Showing general prompts for now.")
        case .unsupportedLanguage:
            String(localized: "Personalised prompts aren't available in your language yet.")
        }
    }
}

extension EnvironmentValues {
    /// The engine views use for moods and prompts. Overridden in tests and previews.
    @Entry var reflectionEngine: any ReflectionEngine = ReflectionEngineFactory.makeDefault()
}
