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

    @Published public var modelDownloadMessage: String = "No download in progress"
    @Published public var modelDownloadFraction: Double = 0
    @Published public var isDownloadingModels: Bool = false

    @Published public var sourcePartialText: String = ""
    @Published public var targetPartialText: String = ""
    @Published public var partnerInputText: String = ""
    @Published public var segments: [InterpretedSegment] = []

    private let modelStore = LocalModelStore.shared
    private let speechService = LocalSpeechStreamingService()
    private let translationService = LocalTranslationService()
    private let speechOutputService = RoutedSpeechOutputService()

    private var stabilizer = TranscriptStabilizer()
    private var runTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var partialTranslationTask: Task<Void, Never>?
    private var userFinalTranslationTask: Task<Void, Never>?
    private var partnerFinalTranslationTask: Task<Void, Never>?
    private var runToken = UUID()
    private var partialRequestGeneration: UInt64 = 0
    private var userFinalRequestGeneration: UInt64 = 0
    private var partnerFinalRequestGeneration: UInt64 = 0
    private var lastPartialTranslationAt: Date = .distantPast

    public init() {
        refreshRouteDiagnostics()
        refreshModelDiagnostics()
    }

    public func start() {
        guard runTask == nil else { return }

        runToken = UUID()
        resetRuntimeState()
        refreshRouteDiagnostics()

        isRunning = true
        statusMessage = "Preparing local models..."

        let token = runToken
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRealtimeLoop(token: token)
        }
    }

    public func stop() {
        runToken = UUID()

        runTask?.cancel()
        runTask = nil

        downloadTask?.cancel()
        downloadTask = nil

        partialTranslationTask?.cancel()
        partialTranslationTask = nil

        userFinalTranslationTask?.cancel()
        userFinalTranslationTask = nil

        partnerFinalTranslationTask?.cancel()
        partnerFinalTranslationTask = nil

        Task { await speechService.stop() }
        speechOutputService.stopAll()

        isRunning = false
        statusMessage = "Stopped"
        refreshRouteDiagnostics()
    }

    public func downloadSelectedPreset() {
        guard downloadTask == nil else { return }

        let preset = config.preset
        modelDownloadMessage = "Downloading \(preset.title) preset..."
        modelDownloadFraction = 0
        isDownloadingModels = true

        downloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.modelStore.ensureDownloaded(for: preset) { [weak self] progress in
                    await self?.applyDownloadProgress(progress)
                }
                self.modelDownloadMessage = "\(preset.title) preset is ready."
                self.modelDownloadFraction = 1
                self.isDownloadingModels = false
                self.downloadTask = nil
            } catch {
                self.errorMessage = self.describeError(error)
                self.modelDownloadMessage = "Download failed."
                self.isDownloadingModels = false
                self.downloadTask = nil
            }
        }
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
                throw InterpretationError.microphonePermissionDenied
            }

            statusMessage = "Checking selected preset..."
            let preset = config.preset
            let urls = try await ensurePresetModelsDownloaded(preset: preset)

            statusMessage = "Loading Whisper and local translator..."
            await speechService.configure(modelURL: urls.speechModelURL)
            try await translationService.configure(modelURL: urls.translationModelURL)

            refreshRouteDiagnostics()
            statusMessage = "Listening (You -> Partner)"

            try await speechService.run { [weak self] update in
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

    private func ensurePresetModelsDownloaded(preset: LocalRealtimePreset) async throws -> LocalPresetModelURLs {
        isDownloadingModels = true
        modelDownloadMessage = "Preparing \(preset.title) preset..."
        modelDownloadFraction = 0

        defer {
            isDownloadingModels = false
        }

        return try await modelStore.ensureDownloaded(for: preset) { [weak self] progress in
            await self?.applyDownloadProgress(progress)
        }
    }

    private func applyDownloadProgress(_ progress: LocalModelDownloadProgress) {
        let stageName = progress.stage.label
        let percent = Int((progress.fractionCompleted * 100).rounded())
        let totalLabel: String
        if let totalBytes = progress.totalBytes {
            totalLabel = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        } else {
            totalLabel = "unknown size"
        }
        modelDownloadMessage = "\(progress.preset.title): \(stageName) \(percent)% of \(totalLabel)"
        modelDownloadFraction = progress.fractionCompleted
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

        partialTranslationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if delaySeconds > 0 {
                let sleepNs = UInt64(delaySeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNs)
            }

            guard !Task.isCancelled, self.runToken == token, self.partialRequestGeneration == generation else { return }
            self.lastPartialTranslationAt = Date()
            await self.translatePartialSegment(
                trimmed,
                sourcePartialSnapshot: partialText,
                token: token,
                generation: generation
            )
        }
    }

    private func translateUserFinalSegment(_ sourceText: String, token: UUID) {
        let started = DispatchTime.now().uptimeNanoseconds

        userFinalRequestGeneration &+= 1
        let generation = userFinalRequestGeneration
        userFinalTranslationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let translated = try await self.translationService.translate(
                    sourceText,
                    source: self.config.sourceLanguage,
                    target: self.config.targetLanguage
                ) { [weak self] partial in
                    await self?.updateTranslatedPartial(
                        partial,
                        sourceSnapshot: sourceText,
                        token: token,
                        generation: generation
                    )
                }

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
        partnerFinalTranslationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let translated = try await self.translationService.translate(
                    sourceText,
                    source: self.config.targetLanguage,
                    target: self.config.sourceLanguage
                ) { [weak self] partial in
                    await self?.updateTranslatedPartial(
                        partial,
                        sourceSnapshot: sourceText,
                        token: token,
                        generation: generation
                    )
                }

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

    private func translatePartialSegment(
        _ sourceText: String,
        sourcePartialSnapshot: String,
        token: UUID,
        generation: UInt64
    ) async {
        do {
            let translated = try await translationService.translate(
                sourceText,
                source: config.sourceLanguage,
                target: config.targetLanguage
            ) { [weak self] partial in
                await self?.updateTranslatedPartial(
                    partial,
                    sourceSnapshot: sourcePartialSnapshot,
                    token: token,
                    generation: generation
                )
            }

            guard runToken == token, partialRequestGeneration == generation else { return }
            if sourcePartialText == sourcePartialSnapshot {
                targetPartialText = translated
            }
        } catch {
            // Partial translation failures should not interrupt the live pipeline.
        }
    }

    private func updateTranslatedPartial(
        _ translatedText: String,
        sourceSnapshot: String,
        token: UUID,
        generation: UInt64
    ) async {
        guard runToken == token else { return }
        guard sourcePartialText == sourceSnapshot || !sourceSnapshot.isEmpty else { return }

        if generation == partialRequestGeneration || generation == userFinalRequestGeneration || generation == partnerFinalRequestGeneration {
            targetPartialText = translatedText
        }
    }

    public func refreshModelDiagnostics() {
        let preset = config.preset
        modelDownloadMessage = "\(preset.title) preset selected. \(preset.estimatedSizeLabel) total."
        modelDownloadFraction = 0
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
        lastPartialTranslationAt = .distantPast
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

        return (error as NSError).localizedDescription
    }
}
