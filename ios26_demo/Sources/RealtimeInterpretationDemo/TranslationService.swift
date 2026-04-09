import Foundation
@preconcurrency import Translation

@available(iOS 26.4, *)
private actor TranslationRequestGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            isBusy = false
        }
    }
}

@available(iOS 26.4, *)
@MainActor
public final class TranslationService {
    private var session: TranslationSession?
    private(set) var activeStrategy: TranslationSession.Strategy?
    private let requestGate = TranslationRequestGate()

    public init() {}

    public func configure(
        source: Locale.Language,
        target: Locale.Language,
        strategy: TranslationSession.Strategy
    ) async throws -> TranslationSession.Strategy {
        let preferredAvailability = LanguageAvailability(preferredStrategy: strategy)
        let status = await preferredAvailability.status(from: source, to: target)
        let pair = pairLabel(source: source, target: target)

        switch status {
        case .unsupported:
            throw InterpretationError.translationPairUnsupported(pair)
        case .installed, .supported:
            break
        @unknown default:
            throw InterpretationError.translationPreflightFailed("Unknown language availability status from Translation framework.")
        }

        do {
            let configured = try await prepareSession(
                source: source,
                target: target,
                strategy: strategy,
                status: status,
                pair: pair
            )
            session = configured
            activeStrategy = strategy
            return strategy
        } catch {
            guard strategy == .highFidelity else {
                throw mapTranslationError(error, pair: pair)
            }

            // High-fidelity models can be unavailable while low-latency models are usable.
            let fallback = TranslationSession.Strategy.lowLatency
            let fallbackAvailability = LanguageAvailability(preferredStrategy: fallback)
            let fallbackStatus = await fallbackAvailability.status(from: source, to: target)
            guard fallbackStatus != .unsupported else {
                throw mapTranslationError(error, pair: pair)
            }

            let fallbackSession = try await prepareSession(
                source: source,
                target: target,
                strategy: fallback,
                status: fallbackStatus,
                pair: pair
            )
            session = fallbackSession
            activeStrategy = fallback
            return fallback
        }
    }

    public func translate(_ sourceText: String) async throws -> String {
        guard let session else {
            throw InterpretationError.translationNotConfigured
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        await requestGate.acquire()
        do {
            let response = try await session.translate(trimmed)
            await requestGate.release()
            return response.targetText
        } catch {
            await requestGate.release()
            throw mapTranslationError(error, pair: pairLabel(source: session.sourceLanguage, target: session.targetLanguage))
        }
    }

    public func cancel() {
        // Avoid hard cancel on TranslationSession while requests are in-flight.
        // Internal service queues can race under abrupt cancellation.
        session = nil
        activeStrategy = nil
    }

    private func prepareSession(
        source: Locale.Language,
        target: Locale.Language,
        strategy: TranslationSession.Strategy,
        status: LanguageAvailability.Status,
        pair: String
    ) async throws -> TranslationSession {
        let configured = TranslationSession(
            installedSource: source,
            target: target,
            preferredStrategy: strategy
        )

        if status == .supported && !configured.canRequestDownloads {
            throw InterpretationError.translationModelNotInstalled(pair)
        }

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await configured.prepareTranslation()
                return configured
            } catch {
                lastError = error
                let nsError = error as NSError
                let isCode16 = nsError.domain == "TranslationErrorDomain" && nsError.code == 16
                guard isCode16, attempt < 2 else {
                    throw mapTranslationError(error, pair: pair)
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        throw mapTranslationError(lastError ?? InterpretationError.translationUnavailable, pair: pair)
    }

    private func mapTranslationError(_ error: Error, pair: String) -> Error {
        if TranslationError.notInstalled ~= error {
            return InterpretationError.translationModelNotInstalled(pair)
        }
        if TranslationError.unsupportedLanguagePairing ~= error ||
            TranslationError.unsupportedSourceLanguage ~= error ||
            TranslationError.unsupportedTargetLanguage ~= error {
            return InterpretationError.translationPairUnsupported(pair)
        }

        let nsError = error as NSError
        if nsError.domain == "TranslationErrorDomain" && nsError.code == 16 {
            return InterpretationError.translationPreflightFailed(
                "Language downloads did not finish (TranslationErrorDomain code 16). Connect to stable Wi-Fi, open Apple Translate once to complete language downloads, then retry."
            )
        }
        if TranslationError.internalError ~= error {
            return InterpretationError.translationPreflightFailed("Translation engine internal error.")
        }

        return error
    }

    private func pairLabel(source: Locale.Language?, target: Locale.Language?) -> String {
        let sourceIdentifier = source?.maximalIdentifier ?? "auto"
        let targetIdentifier = target?.maximalIdentifier ?? "auto"
        return "\(sourceIdentifier) -> \(targetIdentifier)"
    }
}
