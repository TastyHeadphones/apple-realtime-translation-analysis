import Foundation

public enum InterpretationError: LocalizedError {
    case audioSessionConfigurationFailed(String)
    case microphonePermissionDenied
    case speechModelLoadFailed(String)
    case speechEngineStartFailed(String)
    case speechCaptureFailed(String)
    case translationModelLoadFailed(String)
    case translationFailed(String)
    case modelDownloadFailed(String)
    case unsupportedSpeechLocale(String)

    public var errorDescription: String? {
        switch self {
        case .audioSessionConfigurationFailed(let message):
            return "Audio session configuration failed: \(message)"
        case .microphonePermissionDenied:
            return "Microphone permission was denied."
        case .speechModelLoadFailed(let message):
            return "Speech model failed to load: \(message)"
        case .speechEngineStartFailed(let message):
            return "Speech engine failed to start: \(message)"
        case .speechCaptureFailed(let message):
            return "Speech capture failed: \(message)"
        case .translationModelLoadFailed(let message):
            return "Translation model failed to load: \(message)"
        case .translationFailed(let message):
            return "Translation failed: \(message)"
        case .modelDownloadFailed(let message):
            return "Model download failed: \(message)"
        case .unsupportedSpeechLocale(let locale):
            return "Speech input locale is not supported: \(locale)"
        }
    }
}

