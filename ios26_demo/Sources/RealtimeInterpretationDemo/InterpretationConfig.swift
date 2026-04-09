import Foundation
import Translation

public struct InterpretationConfig: Sendable {
    public enum Strategy: String, CaseIterable, Sendable {
        case lowLatency
        case highFidelity

        @available(iOS 26.4, *)
        var translationStrategy: TranslationSession.Strategy {
            switch self {
            case .lowLatency:
                return .lowLatency
            case .highFidelity:
                return .highFidelity
            }
        }
    }

    public var sourceLocaleIdentifier: String
    public var targetLocaleIdentifier: String
    public var strategy: Strategy
    public var partialTranslationThrottleMs: Int
    public var speakTranslatedOutput: Bool

    public init(
        sourceLocaleIdentifier: String = "en-US",
        targetLocaleIdentifier: String = "es-ES",
        strategy: Strategy = .lowLatency,
        partialTranslationThrottleMs: Int = 350,
        speakTranslatedOutput: Bool = false
    ) {
        self.sourceLocaleIdentifier = sourceLocaleIdentifier
        self.targetLocaleIdentifier = targetLocaleIdentifier
        self.strategy = strategy
        self.partialTranslationThrottleMs = partialTranslationThrottleMs
        self.speakTranslatedOutput = speakTranslatedOutput
    }

    public var sourceLocale: Locale {
        Locale(identifier: sourceLocaleIdentifier)
    }

    public var targetLocale: Locale {
        Locale(identifier: targetLocaleIdentifier)
    }

    public var sourceLanguage: Locale.Language {
        sourceLocale.language
    }

    public var targetLanguage: Locale.Language {
        targetLocale.language
    }
}
