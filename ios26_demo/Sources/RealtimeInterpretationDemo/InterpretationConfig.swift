import Foundation

public struct InterpretationConfig: Sendable {
    public enum SupportedLanguage: String, CaseIterable, Identifiable, Sendable {
        case englishUS = "en-US"
        case japanese = "ja-JP"
        case chineseMandarin = "zh-CN"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .englishUS:
                return "English (US)"
            case .japanese:
                return "Japanese"
            case .chineseMandarin:
                return "Chinese (Mandarin)"
            }
        }

        public var locale: Locale {
            Locale(identifier: rawValue)
        }
    }

    public var source: SupportedLanguage
    public var target: SupportedLanguage
    public var preset: LocalRealtimePreset
    public var partialTranslationThrottleMs: Int
    public var speakTranslatedOutput: Bool

    public init(
        source: SupportedLanguage = .englishUS,
        target: SupportedLanguage = .japanese,
        preset: LocalRealtimePreset = .realtime,
        partialTranslationThrottleMs: Int = 350,
        speakTranslatedOutput: Bool = false
    ) {
        self.source = source
        self.target = target
        self.preset = preset
        self.partialTranslationThrottleMs = partialTranslationThrottleMs
        self.speakTranslatedOutput = speakTranslatedOutput

        if self.source == self.target {
            self.target = Self.defaultCompanion(for: self.source)
        }
    }

    public static var supportedLanguages: [SupportedLanguage] {
        SupportedLanguage.allCases
    }

    public static var supportedPresets: [LocalRealtimePreset] {
        LocalRealtimePreset.allCases
    }

    public var sourceLocaleIdentifier: String {
        source.rawValue
    }

    public var targetLocaleIdentifier: String {
        target.rawValue
    }

    public mutating func swapLanguages() {
        (source, target) = (target, source)
    }

    public mutating func enforceDistinctPair(changedSide: Side) {
        guard source == target else { return }
        switch changedSide {
        case .source:
            target = Self.defaultCompanion(for: source)
        case .target:
            source = Self.defaultCompanion(for: target)
        }
    }

    public enum Side {
        case source
        case target
    }

    public var sourceLocale: Locale {
        source.locale
    }

    public var targetLocale: Locale {
        target.locale
    }

    public var sourceLanguage: Locale.Language {
        sourceLocale.language
    }

    public var targetLanguage: Locale.Language {
        targetLocale.language
    }

    public var presetTitle: String {
        preset.title
    }

    public var presetDescription: String {
        preset.subtitle
    }

    public var presetSizeLabel: String {
        preset.estimatedSizeLabel
    }

    private static func defaultCompanion(for language: SupportedLanguage) -> SupportedLanguage {
        switch language {
        case .englishUS:
            return .japanese
        case .japanese:
            return .englishUS
        case .chineseMandarin:
            return .englishUS
        }
    }
}

