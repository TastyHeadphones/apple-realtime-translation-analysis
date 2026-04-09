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
    private var runToken = UUID()
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

        speechService.stop()
        forwardTranslationService.cancel()
        reverseTranslationService.cancel()
        speechOutputService.stopAll()

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
            try await forwardTranslationService.configure(
                source: config.sourceLanguage,
                target: config.targetLanguage,
                strategy: config.strategy.translationStrategy
            )
            try await reverseTranslationService.configure(
                source: config.targetLanguage,
                target: config.sourceLanguage,
                strategy: config.strategy.translationStrategy
            )

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
                errorMessage = error.localizedDescription
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
            return
        }

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

            guard !Task.isCancelled, self.runToken == token else { return }
            self.lastPartialTranslationAt = Date()

            do {
                let translated = try await self.forwardTranslationService.translate(trimmed)
                guard !Task.isCancelled, self.runToken == token else { return }

                if self.sourcePartialText == partialText {
                    self.targetPartialText = translated
                }
            } catch {
                // Partial translation failures should not interrupt the live pipeline.
            }
        }
    }

    private func translateUserFinalSegment(_ sourceText: String, token: UUID) {
        let started = DispatchTime.now().uptimeNanoseconds

        Task { [weak self] in
            guard let self else { return }

            do {
                let translated = try await self.forwardTranslationService.translate(sourceText)
                guard self.runToken == token else { return }

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
                guard self.runToken == token else { return }
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Error"
            }
        }
    }

    private func translatePartnerSegment(_ sourceText: String, token: UUID) {
        let started = DispatchTime.now().uptimeNanoseconds

        Task { [weak self] in
            guard let self else { return }

            do {
                let translated = try await self.reverseTranslationService.translate(sourceText)
                guard self.runToken == token else { return }

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
                guard self.runToken == token else { return }
                self.errorMessage = error.localizedDescription
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
        lastPartialTranslationAt = .distantPast
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
