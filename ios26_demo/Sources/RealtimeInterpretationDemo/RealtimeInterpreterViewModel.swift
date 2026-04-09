import AVFAudio
import Foundation
import SwiftUI

@available(iOS 26.4, *)
@MainActor
public final class RealtimeInterpreterViewModel: ObservableObject {
    @Published public var config = InterpretationConfig()
    @Published public var statusMessage: String = "Idle"
    @Published public var errorMessage: String?
    @Published public var isRunning: Bool = false

    @Published public var audioRouteSummary: String = "No active output route"
    @Published public var partnerPlaybackSummary: String = "System default"
    @Published public var mePlaybackSummary: String = "System default"
    @Published public var isDualRouteActive: Bool = false

    @Published public var sourcePartialText: String = ""
    @Published public var targetPartialText: String = ""
    @Published public var partnerInputText: String = ""
    @Published public var segments: [InterpretedSegment] = []

    private let speechService = SpeechStreamingService()
    private let forwardTranslationService = TranslationService()
    private let reverseTranslationService = TranslationService()
    private let speechOutputService = RoutedSpeechOutputService()

    private var stabilizer = TranscriptStabilizer()
    private var runTask: Task<Void, Never>?
    private var partialTranslationTask: Task<Void, Never>?
    private var userFinalTranslationTask: Task<Void, Never>?
    private var partnerFinalTranslationTask: Task<Void, Never>?
    private var runToken = UUID()
    private var partialRequestGeneration: UInt64 = 0
    private var userFinalRequestGeneration: UInt64 = 0
    private var partnerFinalRequestGeneration: UInt64 = 0
    private var reverseTranslationPrepared = false
    private var lastPartialTranslationAt: Date = .distantPast

    public init() {
        refreshRouteDiagnostics()
    }

    public func start() {
        guard runTask == nil else { return }

        runToken = UUID()
        resetRuntimeState()
        refreshRouteDiagnostics()

        isRunning = true
        statusMessage = "Preparing..."

        let token = runToken
        runTask = Task { [weak self] in
            guard let self else { return }
            await self.runRealtimeLoop(token: token)
        }
    }

    public func stop() {
        runToken = UUID()

        runTask?.cancel()
        runTask = nil

        partialTranslationTask?.cancel()
        partialTranslationTask = nil

        userFinalTranslationTask = nil

        partnerFinalTranslationTask = nil

        speechService.stop()
        forwardTranslationService.cancel()
        reverseTranslationService.cancel()
        speechOutputService.stopAll()
        reverseTranslationPrepared = false

        isRunning = false
        statusMessage = "Stopped"
        refreshRouteDiagnostics()
    }

    public func submitPartnerText() {
        let sourceText = partnerInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }
        guard isRunning else {
            errorMessage = "Start the interpreter before sending partner text."
            return
        }

        partnerInputText = ""
        translatePartnerSegment(sourceText, token: runToken)
    }

    public var toPartnerSegments: [InterpretedSegment] {
        segments.filter { $0.direction == .toPartner }
    }

    public var toMeSegments: [InterpretedSegment] {
        segments.filter { $0.direction == .toMe }
    }

    private func runRealtimeLoop(token: UUID) async {
        do {
            let micGranted = await requestMicrophonePermission()
            guard micGranted else {
                throw InterpretationError.audioSessionConfigurationFailed("Microphone permission was denied.")
            }

            statusMessage = "Preparing translation models..."
            let forwardStrategy = try await forwardTranslationService.configure(
                source: config.sourceLanguage,
                target: config.targetLanguage,
                strategy: config.strategy.translationStrategy
            )
            reverseTranslationPrepared = false

            if forwardStrategy != config.strategy.translationStrategy {
                errorMessage = "High-fidelity model was unavailable for at least one direction; using low-latency translation."
            }

            refreshRouteDiagnostics()
            statusMessage = "Listening (You -> Partner)"

            try await speechService.run(locale: config.sourceLocale) { [weak self] update in
                guard let self else { return }
                await self.handleTranscript(update, token: token)
            }
        } catch is CancellationError {
            // Expected during stop.
        } catch {
            if runToken == token {
                errorMessage = describeError(error)
                statusMessage = "Error"
            }
        }

        if runToken == token {
            runTask = nil
            isRunning = false
            if errorMessage == nil {
                statusMessage = "Idle"
            }
        }
    }

    private func handleTranscript(_ update: TranscriptUpdate, token: UUID) async {
        guard runToken == token else { return }

        let stabilized = stabilizer.consume(update)

        if let finalized = stabilized.finalizedTail, !finalized.isEmpty {
            partialTranslationTask?.cancel()
            partialTranslationTask = nil

            sourcePartialText = ""
            targetPartialText = ""
            translateUserFinalSegment(finalized, token: token)
            return
        }

        sourcePartialText = stabilized.partialTail
        schedulePartialTranslation(for: stabilized.partialTail, token: token)
    }

    private func schedulePartialTranslation(for partialText: String, token: UUID) {
        let trimmed = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            partialTranslationTask?.cancel()
            partialTranslationTask = nil
            targetPartialText = ""
            partialRequestGeneration &+= 1
            return
        }

        partialRequestGeneration &+= 1
        let generation = partialRequestGeneration
        partialTranslationTask?.cancel()

        let now = Date()
        let throttleSeconds = TimeInterval(config.partialTranslationThrottleMs) / 1_000
        let elapsed = now.timeIntervalSince(lastPartialTranslationAt)
        let delaySeconds = max(0, throttleSeconds - elapsed)

        partialTranslationTask = Task { [weak self] in
            guard let self else { return }

            if delaySeconds > 0 {
                let sleepNs = UInt64(delaySeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNs)
            }

            guard !Task.isCancelled, self.runToken == token, self.partialRequestGeneration == generation else { return }
            self.lastPartialTranslationAt = Date()

            // Run translation without exposing cancellation to TranslationSession internals.
            Task { [weak self] in
                await self?.translatePartialSegment(
                    trimmed,
                    sourcePartialSnapshot: partialText,
                    token: token,
                    generation: generation
                )
            }
        }
    }

    private func translateUserFinalSegment(_ sourceText: String, token: UUID) {
        let started = DispatchTime.now().uptimeNanoseconds

        userFinalRequestGeneration &+= 1
        let generation = userFinalRequestGeneration
        userFinalTranslationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let translated = try await self.forwardTranslationService.translate(sourceText)
                guard self.runToken == token, self.userFinalRequestGeneration == generation else { return }

                let ended = DispatchTime.now().uptimeNanoseconds
                let latencyMs = Int((ended - started) / 1_000_000)

                self.refreshRouteDiagnostics()
                let segment = InterpretedSegment(
                    direction: .toPartner,
                    sourceText: sourceText,
                    targetText: translated,
                    translationLatencyMs: latencyMs,
                    playbackRouteLabel: self.partnerPlaybackSummary
                )
                self.segments.append(segment)

                if self.config.speakTranslatedOutput {
                    self.speechOutputService.speakToPartnerOnPhone(
                        translated,
                        language: self.config.targetLocaleIdentifier
                    )
                    self.refreshRouteDiagnostics()
                }
            } catch {
                guard self.runToken == token, self.userFinalRequestGeneration == generation else { return }
                self.errorMessage = self.describeError(error)
                self.statusMessage = "Error"
            }
        }
    }

    private func translatePartnerSegment(_ sourceText: String, token: UUID) {
        let started = DispatchTime.now().uptimeNanoseconds

        partnerFinalRequestGeneration &+= 1
        let generation = partnerFinalRequestGeneration
        partnerFinalTranslationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let reverseUsedFallback = try await self.configureReverseTranslationIfNeeded()
                if reverseUsedFallback {
                    self.errorMessage = "High-fidelity model was unavailable for partner-to-you direction; using low-latency translation."
                }

                let translated = try await self.reverseTranslationService.translate(sourceText)
                guard self.runToken == token, self.partnerFinalRequestGeneration == generation else { return }

                let ended = DispatchTime.now().uptimeNanoseconds
                let latencyMs = Int((ended - started) / 1_000_000)

                self.refreshRouteDiagnostics()
                let segment = InterpretedSegment(
                    direction: .toMe,
                    sourceText: sourceText,
                    targetText: translated,
                    translationLatencyMs: latencyMs,
                    playbackRouteLabel: self.mePlaybackSummary
                )
                self.segments.append(segment)

                if self.config.speakTranslatedOutput {
                    self.speechOutputService.speakToMeOnEarphones(
                        translated,
                        language: self.config.sourceLocaleIdentifier
                    )
                    self.refreshRouteDiagnostics()
                }
            } catch {
                guard self.runToken == token, self.partnerFinalRequestGeneration == generation else { return }
                self.errorMessage = self.describeError(error)
                self.statusMessage = "Error"
            }
        }
    }

    private func refreshRouteDiagnostics() {
        speechOutputService.refreshRouting()
        audioRouteSummary = speechOutputService.routeSummary
        partnerPlaybackSummary = speechOutputService.partnerPlaybackSummary
        mePlaybackSummary = speechOutputService.mePlaybackSummary
        isDualRouteActive = speechOutputService.dualRouteActive
    }

    private func resetRuntimeState() {
        errorMessage = nil
        sourcePartialText = ""
        targetPartialText = ""
        partnerInputText = ""
        segments = []
        stabilizer.reset()
        partialRequestGeneration = 0
        userFinalRequestGeneration = 0
        partnerFinalRequestGeneration = 0
        reverseTranslationPrepared = false
        lastPartialTranslationAt = .distantPast
    }

    private func translatePartialSegment(
        _ sourceText: String,
        sourcePartialSnapshot: String,
        token: UUID,
        generation: UInt64
    ) async {
        do {
            let translated = try await forwardTranslationService.translate(sourceText)
            guard runToken == token, partialRequestGeneration == generation else { return }

            if sourcePartialText == sourcePartialSnapshot {
                targetPartialText = translated
            }
        } catch {
            // Partial translation failures should not interrupt the live pipeline.
        }
    }

    private func configureReverseTranslationIfNeeded() async throws -> Bool {
        let preferredStrategy = config.strategy.translationStrategy

        if reverseTranslationPrepared {
            if let active = reverseTranslationService.activeStrategy {
                return active != preferredStrategy
            }
            return false
        }

        let configuredStrategy = try await reverseTranslationService.configure(
            source: config.targetLanguage,
            target: config.sourceLanguage,
            strategy: preferredStrategy
        )
        reverseTranslationPrepared = true
        return configuredStrategy != preferredStrategy
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func describeError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }

        let nsError = error as NSError
        if nsError.domain == "TranslationErrorDomain" && nsError.code == 16 {
            return "Translation resources are not ready (code 16). Connect to stable Wi-Fi, open Apple Translate once to complete language downloads, then restart."
        }

        return nsError.localizedDescription
    }
}
