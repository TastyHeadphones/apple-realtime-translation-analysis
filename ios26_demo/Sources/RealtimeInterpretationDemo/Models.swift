import Foundation

public enum ConversationDirection: String, Sendable {
    case toPartner
    case toMe
}

public struct InterpretedSegment: Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let direction: ConversationDirection
    public let sourceText: String
    public let targetText: String
    public let translationLatencyMs: Int
    public let playbackRouteLabel: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        direction: ConversationDirection,
        sourceText: String,
        targetText: String,
        translationLatencyMs: Int,
        playbackRouteLabel: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.direction = direction
        self.sourceText = sourceText
        self.targetText = targetText
        self.translationLatencyMs = translationLatencyMs
        self.playbackRouteLabel = playbackRouteLabel
    }
}

public struct TranscriptUpdate: Sendable {
    public let fullText: String
    public let isFinal: Bool

    public init(fullText: String, isFinal: Bool) {
        self.fullText = fullText
        self.isFinal = isFinal
    }
}

public struct StabilizedUpdate: Sendable {
    public let partialTail: String
    public let finalizedTail: String?

    public init(partialTail: String, finalizedTail: String?) {
        self.partialTail = partialTail
        self.finalizedTail = finalizedTail
    }
}
