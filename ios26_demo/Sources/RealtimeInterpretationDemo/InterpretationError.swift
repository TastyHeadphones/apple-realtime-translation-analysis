import Foundation

public enum InterpretationError: LocalizedError {
    case audioSessionConfigurationFailed(String)
    case appleIntelligenceUnavailable(String)
    case speechEngineStartFailed(String)
    case speechRecognitionUnavailable
    case unsupportedSpeechLocale(String)
    case speechAssetsUnavailable(String)
    case speechInputFormatUnavailable(String)
    case translationNotConfigured
    case translationUnavailable
    case translationPairUnsupported(String)
    case translationModelNotInstalled(String)
    case translationPreflightFailed(String)

    public var errorDescription: String? {
        switch self {
        case .audioSessionConfigurationFailed(let message):
            return "Audio session configuration failed: \(message)"
        case .appleIntelligenceUnavailable(let details):
            return "Apple Intelligence is not ready for live speech translation. \(details)"
        case .speechEngineStartFailed(let message):
            return "Speech engine failed to start: \(message)"
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this device."
        case .unsupportedSpeechLocale(let locale):
            return "Speech recognition locale is not supported or not installed: \(locale)"
        case .speechAssetsUnavailable(let details):
            return "Speech assets are not ready. \(details)"
        case .speechInputFormatUnavailable(let details):
            return "Speech input format is not supported. \(details)"
        case .translationNotConfigured:
            return "Translation session is not configured."
        case .translationUnavailable:
            return "Translation session is unavailable for the selected language pair."
        case .translationPairUnsupported(let pair):
            return "Translation pair is unsupported: \(pair)."
        case .translationModelNotInstalled(let pair):
            return "Translation model is not installed for \(pair). Connect to Wi-Fi, open Apple Translate to finish language downloads, and retry."
        case .translationPreflightFailed(let details):
            return "Translation preflight failed. \(details)"
        }
    }
}
