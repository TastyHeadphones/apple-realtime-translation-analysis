import AVFAudio
import Foundation
@preconcurrency import SwiftWhisper

private final class AudioCaptureBuffer {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var lastVoiceActivity: Date = .distantPast

    private let maxSamples: Int
    private let voiceThreshold: Float = 0.012

    init(maxDurationSeconds: Double = 10, sampleRate: Double = 16_000) {
        maxSamples = Int(maxDurationSeconds * sampleRate)
    }

    func append(_ newSamples: [Float]) {
        guard !newSamples.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        let energy = rms(of: newSamples)
        if energy >= voiceThreshold {
            lastVoiceActivity = Date()
        }
        samples.append(contentsOf: newSamples)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    func snapshot() -> (samples: [Float], lastVoiceActivity: Date) {
        lock.lock()
        let snapshot = samples
        let voiceActivity = lastVoiceActivity
        lock.unlock()
        return (snapshot, voiceActivity)
    }

    func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lastVoiceActivity = .distantPast
        lock.unlock()
    }

    private func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + ($1 * $1) }
        return sqrt(sum / Float(samples.count))
    }
}

private func convertPCMBuffer(_ buffer: AVAudioPCMBuffer, targetSampleRate: Double = 16_000) -> [Float]? {
    guard buffer.frameLength > 0 else { return nil }
    guard let channelData = buffer.floatChannelData else { return nil }

    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard channelCount > 0 else { return nil }

    var mono = [Float]()
    mono.reserveCapacity(frameCount)

    if channelCount == 1 {
        mono.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameCount))
    } else {
        for frameIndex in 0..<frameCount {
            var total: Float = 0
            for channelIndex in 0..<channelCount {
                total += channelData[channelIndex][frameIndex]
            }
            mono.append(total / Float(channelCount))
        }
    }

    let sourceRate = buffer.format.sampleRate
    guard sourceRate > 0 else { return mono }
    if abs(sourceRate - targetSampleRate) < 0.5 {
        return mono
    }

    let outputCount = max(1, Int((Double(mono.count) * targetSampleRate / sourceRate).rounded()))
    var output = [Float](repeating: 0, count: outputCount)
    let ratio = sourceRate / targetSampleRate

    for outputIndex in 0..<outputCount {
        let sourcePosition = Double(outputIndex) * ratio
        let lowerIndex = min(max(Int(floor(sourcePosition)), 0), mono.count - 1)
        let upperIndex = min(lowerIndex + 1, mono.count - 1)
        let fraction = Float(sourcePosition - Double(lowerIndex))
        output[outputIndex] = mono[lowerIndex] * (1 - fraction) + mono[upperIndex] * fraction
    }

    return output
}

@available(iOS 26.0, *)
public actor LocalSpeechStreamingService {
    private let engine = AVAudioEngine()
    private let captureBuffer = AudioCaptureBuffer()
    private var whisper: Whisper?
    private var configuredModelURL: URL?
    private var isRunning = false

    public init() {}

    public func configure(modelURL: URL) {
        if configuredModelURL == modelURL, whisper != nil {
            return
        }

        whisper = Whisper(fromFileURL: modelURL)
        configuredModelURL = modelURL
    }

    public func run(
        onUpdate: @escaping @Sendable (TranscriptUpdate) async -> Void
    ) async throws {
        guard let whisper else {
            throw InterpretationError.speechModelLoadFailed("Speech model is not configured.")
        }

        defer {
            stop()
        }

        try configureAudioSession()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw InterpretationError.speechCaptureFailed("Failed to create 16 kHz audio format.")
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [captureBuffer] buffer, _ in
            guard let samples = convertPCMBuffer(buffer, targetSampleRate: targetFormat.sampleRate) else {
                return
            }
            captureBuffer.append(samples)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw InterpretationError.speechEngineStartFailed(error.localizedDescription)
        }

        isRunning = true
        defer {
            isRunning = false
        }

        try await monitorLoop(whisper: whisper, onUpdate: onUpdate)
    }

    public func stop() {
        captureBuffer.reset()
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        isRunning = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func monitorLoop(
        whisper: Whisper,
        onUpdate: @escaping @Sendable (TranscriptUpdate) async -> Void
    ) async throws {
        var lastPartialEmission = Date.distantPast

        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 350_000_000)

            let snapshot = captureBuffer.snapshot()
            guard snapshot.samples.count >= 4_000 else { continue }

            let timeSinceVoice = Date().timeIntervalSince(snapshot.lastVoiceActivity)

            if timeSinceVoice >= 0.9 {
                let text = try await transcribe(samples: snapshot.samples, whisper: whisper)
                await onUpdate(TranscriptUpdate(fullText: text, isFinal: true))
                captureBuffer.reset()
                lastPartialEmission = .distantPast
                continue
            }

            guard Date().timeIntervalSince(lastPartialEmission) >= 0.45 else { continue }
            let window = Array(snapshot.samples.suffix(16_000 * 6))
            let text = try await transcribe(samples: window, whisper: whisper)
            await onUpdate(TranscriptUpdate(fullText: text, isFinal: false))
            lastPartialEmission = Date()
        }
    }

    private func transcribe(samples: [Float], whisper: Whisper) async throws -> String {
        guard !samples.isEmpty else { return "" }
        do {
            let segments = try await whisper.transcribe(audioFrames: samples)
            return segments
                .map(\.text)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } catch {
            throw InterpretationError.speechCaptureFailed(error.localizedDescription)
        }
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
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
