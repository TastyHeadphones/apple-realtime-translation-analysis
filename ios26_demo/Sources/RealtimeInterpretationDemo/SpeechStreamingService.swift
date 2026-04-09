import AVFAudio
import Foundation
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

        try configureAudioSession()

        let transcriber = SpeechTranscriber(
            locale: selectedLocale,
            preset: .timeIndexedProgressiveTranscription
        )
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .whileInUse)
        )

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let bridge = AnalyzerInputBridge()
        inputBridge = bridge
        let inputStream = makeAnalyzerInputStream(engine: engine, inputFormat: inputFormat, bridge: bridge)

        try await analyzer.prepareToAnalyze(in: inputFormat)

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
}
