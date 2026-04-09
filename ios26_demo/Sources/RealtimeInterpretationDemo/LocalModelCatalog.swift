import Foundation

public enum LocalRealtimePreset: String, CaseIterable, Identifiable, Sendable {
    case realtime
    case balanced
    case quality

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .realtime:
            return "Realtime"
        case .balanced:
            return "Balanced"
        case .quality:
            return "Quality"
        }
    }

    public var subtitle: String {
        switch self {
        case .realtime:
            return "Fastest response, smallest download"
        case .balanced:
            return "Best default for live interpretation"
        case .quality:
            return "Higher quality, heavier model"
        }
    }

    public var speechModel: WhisperModelOption {
        switch self {
        case .realtime:
            return .baseQ5
        case .balanced, .quality:
            return .smallQ5
        }
    }

    public var translationModel: TranslationModelOption {
        switch self {
        case .realtime:
            return .q4
        case .balanced:
            return .q4
        case .quality:
            return .q6
        }
    }

    public var estimatedSizeBytes: Int64 {
        speechModel.approximateSizeBytes + translationModel.approximateSizeBytes
    }

    public var estimatedSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: estimatedSizeBytes, countStyle: .file)
    }
}

public enum WhisperModelOption: String, CaseIterable, Identifiable, Sendable {
    case baseQ5
    case smallQ5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .baseQ5:
            return "Whisper Base Q5"
        case .smallQ5:
            return "Whisper Small Q5"
        }
    }

    public var fileName: String {
        switch self {
        case .baseQ5:
            return "ggml-base-q5_1.bin"
        case .smallQ5:
            return "ggml-small-q5_1.bin"
        }
    }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)?download=true")!
    }

    public var approximateSizeBytes: Int64 {
        switch self {
        case .baseQ5:
            return 155_000_000
        case .smallQ5:
            return 488_000_000
        }
    }

    public var stageLabel: String {
        "Speech model"
    }
}

public enum TranslationModelOption: String, CaseIterable, Identifiable, Sendable {
    case q4
    case q6

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .q4:
            return "Qwen 0.5B Q4"
        case .q6:
            return "Qwen 0.5B Q6"
        }
    }

    public var fileName: String {
        switch self {
        case .q4:
            return "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
        case .q6:
            return "Qwen2.5-0.5B-Instruct-Q6_K.gguf"
        }
    }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/lmstudio-community/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/\(fileName)?download=true")!
    }

    public var approximateSizeBytes: Int64 {
        switch self {
        case .q4:
            return 413_000_000
        case .q6:
            return 540_000_000
        }
    }

    public var stageLabel: String {
        "Translation model"
    }
}

