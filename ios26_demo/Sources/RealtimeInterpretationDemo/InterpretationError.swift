import Foundation

public enum InterpretationError: LocalizedError {
    case audioSessionConfigurationFailed(String)
    case speechEngineStartFailed(String)
    case speechRecognitionUnavailable
    case unsupportedSpeechLocale(String)
    case translationNotConfigured
    case translationUnavailable

    public var errorDescription: String? {
        switch self {
        case .audioSessionConfigurationFailed(let message):
            return "Audio session configuration failed: \(message)"
        case .speechEngineStartFailed(let message):
            return "Speech engine failed to start: \(message)"
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this device."
        case .unsupportedSpeechLocale(let locale):
            return "Speech recognition locale is not supported or not installed: \(locale)"
        case .translationNotConfigured:
            return "Translation session is not configured."
        case .translationUnavailable:
            return "Translation session is unavailable for the selected language pair."
        }
    }
}
