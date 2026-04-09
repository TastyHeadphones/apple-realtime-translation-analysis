import AVFAudio
import Foundation
import FoundationModels
import Speech

private final class AnalyzerInputBridge {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?

    func setContinuation(_ continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }

    func yield(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        guard let continuation else { return }
        continuation.yield(AnalyzerInput(buffer: buffer))
    }
}

private func makeAnalyzerInputStream(
    engine: AVAudioEngine,
    inputFormat: AVAudioFormat,
    bridge: AnalyzerInputBridge
) -> AsyncThrowingStream<AnalyzerInput, Error> {
    AsyncThrowingStream { continuation in
        bridge.setContinuation(continuation)

        engine.inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
            guard let copied = copyPCMBuffer(buffer) else { return }
            bridge.yield(copied)
        }
    }
}

private func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copied = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
        return nil
    }

    copied.frameLength = buffer.frameLength

    let channelCount = Int(buffer.format.channelCount)
    let frameCount = Int(buffer.frameLength)

    if let src = buffer.floatChannelData, let dst = copied.floatChannelData {
        for channel in 0..<channelCount {
            dst[channel].update(from: src[channel], count: frameCount)
        }
        return copied
    }

    if let src = buffer.int16ChannelData, let dst = copied.int16ChannelData {
        for channel in 0..<channelCount {
            dst[channel].update(from: src[channel], count: frameCount)
        }
        return copied
    }

    return nil
}

@available(iOS 26.0, *)
@MainActor
public final class SpeechStreamingService {
    private let engine = AVAudioEngine()
    private var inputBridge: AnalyzerInputBridge?
    private var analyzerTask: Task<Void, Error>?
    private var resultTask: Task<Void, Error>?

    public init() {}

    public func run(
        locale: Locale,
        onUpdate: @escaping @Sendable (TranscriptUpdate) async -> Void
    ) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw InterpretationError.speechRecognitionUnavailable
        }

        guard let selectedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw InterpretationError.unsupportedSpeechLocale(locale.identifier)
        }

        let transcriber = SpeechTranscriber(
            locale: selectedLocale,
            preset: .timeIndexedProgressiveTranscription
        )
        let modules: [any Speech.SpeechModule] = [transcriber]

        try await preflightSpeechRuntime(
            selectedLocale: selectedLocale,
            transcriber: transcriber
        )

        try configureAudioSession()

        let inputFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: engine.inputNode.outputFormat(forBus: 0)
        )

        guard let analysisFormat = inputFormat else {
            throw InterpretationError.speechInputFormatUnavailable(
                "No compatible audio format was reported for \(selectedLocale.identifier)."
            )
        }

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .whileInUse)
        )

        let bridge = AnalyzerInputBridge()
        inputBridge = bridge
        let inputStream = makeAnalyzerInputStream(engine: engine, inputFormat: analysisFormat, bridge: bridge)

        try await analyzer.prepareToAnalyze(in: analysisFormat)

        resultTask = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                await onUpdate(TranscriptUpdate(fullText: text, isFinal: result.isFinal))
            }
        }

        analyzerTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw InterpretationError.speechEngineStartFailed(error.localizedDescription)
        }

        if let analyzerTask {
            try await analyzerTask.value
        }

        if let resultTask {
            try await resultTask.value
        }
    }

    public func stop() {
        inputBridge?.finish()
        inputBridge = nil

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }

        analyzerTask?.cancel()
        analyzerTask = nil

        resultTask?.cancel()
        resultTask = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()

        do {
            if #available(iOS 26.2, *) {
                do {
                    try session.setCategory(
                        .multiRoute,
                        mode: .dualRoute,
                        options: [.allowBluetoothHFP]
                    )
                    try session.setPreferredSampleRate(16_000)
                    if session.isEchoCancelledInputAvailable {
                        _ = try? session.setPrefersEchoCancelledInput(true)
                    }
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    return
                } catch {
                    // Fall through to broad compatibility configuration.
                }
            }

            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker, .duckOthers]
            )
            try session.setPreferredSampleRate(16_000)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw InterpretationError.audioSessionConfigurationFailed(error.localizedDescription)
        }
        #endif
    }

    private func preflightSpeechRuntime(
        selectedLocale: Locale,
        transcriber: SpeechTranscriber
    ) async throws {
        let modules: [any Speech.SpeechModule] = [transcriber]
        var modelAvailability = SystemLanguageModel.default.availability
        var assetStatus = await AssetInventory.status(forModules: modules)

        let shouldInstallAssets: Bool
        switch modelAvailability {
        case .available:
            shouldInstallAssets = assetStatus != .installed
        case .unavailable(.modelNotReady):
            shouldInstallAssets = true
        case .unavailable:
            shouldInstallAssets = false
        }

        if shouldInstallAssets {
            try await installSpeechAssetsIfNeeded(for: modules, locale: selectedLocale)
            modelAvailability = SystemLanguageModel.default.availability
            assetStatus = await AssetInventory.status(forModules: modules)
        }

        guard case .available = modelAvailability else {
            throw InterpretationError.appleIntelligenceUnavailable(
                descriptionForAvailability(modelAvailability, locale: selectedLocale)
            )
        }

        guard SystemLanguageModel.default.supportsLocale(selectedLocale) else {
            throw InterpretationError.appleIntelligenceUnavailable(
                "The current Apple Intelligence model does not support \(selectedLocale.identifier) on this device."
            )
        }

        guard assetStatus == .installed else {
            throw InterpretationError.speechAssetsUnavailable(
                "Speech assets for \(selectedLocale.identifier) are \(assetStatus)."
            )
        }

        let compatibleFormats = await transcriber.availableCompatibleAudioFormats
        guard !compatibleFormats.isEmpty else {
            throw InterpretationError.speechInputFormatUnavailable(
                "The speech transcriber reported no compatible audio formats for \(selectedLocale.identifier)."
            )
        }
    }

    private func installSpeechAssetsIfNeeded(
        for modules: [any Speech.SpeechModule],
        locale: Locale
    ) async throws {
        let status = await AssetInventory.status(forModules: modules)
        guard status != .installed else {
            return
        }

        if let request = try? await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        } else {
            var currentStatus = status
            for _ in 0..<10 where currentStatus == .downloading {
                try await Task.sleep(nanoseconds: 500_000_000)
                currentStatus = await AssetInventory.status(forModules: modules)
            }

            guard currentStatus == .installed else {
                throw InterpretationError.speechAssetsUnavailable(
                    "Speech assets for \(locale.identifier) are \(currentStatus)."
                )
            }
        }

        let finalStatus = await AssetInventory.status(forModules: modules)
        guard finalStatus == .installed else {
            throw InterpretationError.speechAssetsUnavailable(
                "Speech assets for \(locale.identifier) are \(finalStatus)."
            )
        }
    }

    private func descriptionForAvailability(
        _ availability: SystemLanguageModel.Availability,
        locale: Locale
    ) -> String {
        switch availability {
        case .available:
            return "Apple Intelligence is available."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device is not eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is not enabled or is unavailable for the current region or Siri language configuration."
            case .modelNotReady:
                return "Apple Intelligence is still preparing the language model for \(locale.identifier)."
            @unknown default:
                return "Apple Intelligence is unavailable for an unknown reason."
            }
        }
    }
}
