import Foundation
@preconcurrency import Translation

@available(iOS 26.4, *)
@MainActor
public final class TranslationService {
    private var session: TranslationSession?

    public init() {}

    public func configure(
        source: Locale.Language,
        target: Locale.Language,
        strategy: TranslationSession.Strategy
    ) async throws {
        let configured = TranslationSession(
            installedSource: source,
            target: target,
            preferredStrategy: strategy
        )

        try await configured.prepareTranslation()
        session = configured
    }

    public func translate(_ sourceText: String) async throws -> String {
        guard let session else {
            throw InterpretationError.translationNotConfigured
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let response = try await session.translate(trimmed)
        return response.targetText
    }

    public func cancel() {
        session?.cancel()
        session = nil
    }
}
