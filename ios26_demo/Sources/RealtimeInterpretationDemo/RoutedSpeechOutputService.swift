import AVFAudio
import Foundation

@available(iOS 26.0, *)
@MainActor
public final class RoutedSpeechOutputService {
    private let partnerSynthesizer = AVSpeechSynthesizer()
    private let meSynthesizer = AVSpeechSynthesizer()

    public private(set) var routeSummary: String = "No active output route"
    public private(set) var partnerPlaybackSummary: String = "System default"
    public private(set) var mePlaybackSummary: String = "System default"
    public private(set) var dualRouteActive: Bool = false

    public init() {}

    public func refreshRouting() {
        let route = AVAudioSession.sharedInstance().currentRoute
        routeSummary = describeRoute(route.outputs)

        let speakerOutputs = route.outputs.filter {
            $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver
        }
        let personalOutputs = route.outputs.filter {
            switch $0.portType {
            case .headphones, .headsetMic, .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
                return true
            default:
                return false
            }
        }

        let speakerChannels = channels(for: speakerOutputs)
        let personalChannels = channels(for: personalOutputs)

        partnerSynthesizer.outputChannels = speakerChannels.isEmpty ? nil : speakerChannels
        meSynthesizer.outputChannels = personalChannels.isEmpty ? nil : personalChannels

        partnerPlaybackSummary = speakerOutputs.isEmpty ? "System default" : describeRoute(speakerOutputs)
        mePlaybackSummary = personalOutputs.isEmpty ? "System default" : describeRoute(personalOutputs)
        dualRouteActive = !speakerOutputs.isEmpty && !personalOutputs.isEmpty
    }

    public func speakToPartnerOnPhone(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        refreshRouting()
        speak(trimmed, language: language, synthesizer: partnerSynthesizer)
    }

    public func speakToMeOnEarphones(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        refreshRouting()
        speak(trimmed, language: language, synthesizer: meSynthesizer)
    }

    public func stopAll() {
        partnerSynthesizer.stopSpeaking(at: .immediate)
        meSynthesizer.stopSpeaking(at: .immediate)
    }

    private func speak(_ text: String, language: String, synthesizer: AVSpeechSynthesizer) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.speak(utterance)
    }

    private func channels(for ports: [AVAudioSessionPortDescription]) -> [AVAudioSessionChannelDescription] {
        ports.flatMap { $0.channels ?? [] }
    }

    private func describeRoute(_ ports: [AVAudioSessionPortDescription]) -> String {
        guard !ports.isEmpty else { return "No active output route" }
        return ports.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
    }
}
