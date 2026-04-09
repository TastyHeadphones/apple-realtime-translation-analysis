import SwiftUI

@available(iOS 26.4, *)
public struct RealtimeInterpreterView: View {
    @StateObject private var viewModel: RealtimeInterpreterViewModel

    public init(viewModel: @autoclosure @escaping () -> RealtimeInterpreterViewModel = RealtimeInterpreterViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    configurationSection
                    liveSection
                    partnerInputSection
                    finalSections
                    diagnosticsSection
                }
                .padding(16)
            }
            .navigationTitle("Live Translation")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isRunning {
                        Button("Stop") {
                            viewModel.stop()
                        }
                        .tint(.red)
                    } else {
                        Button("Start") {
                            viewModel.start()
                        }
                    }
                }
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation Setup")
                .font(.headline)

            HStack {
                TextField("Your language locale (e.g. en-US)", text: $viewModel.config.sourceLocaleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.secondary)

                TextField("Partner language locale (e.g. es-ES)", text: $viewModel.config.targetLocaleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Translation strategy", selection: $viewModel.config.strategy) {
                Text("Low Latency").tag(InterpretationConfig.Strategy.lowLatency)
                Text("High Fidelity").tag(InterpretationConfig.Strategy.highFidelity)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Partial throttle: \(viewModel.config.partialTranslationThrottleMs) ms")
                Spacer()
            }

            Slider(
                value: Binding(
                    get: { Double(viewModel.config.partialTranslationThrottleMs) },
                    set: { viewModel.config.partialTranslationThrottleMs = Int($0.rounded()) }
                ),
                in: 150...1_200,
                step: 50
            )

            Toggle("Speak translated output", isOn: $viewModel.config.speakTranslatedOutput)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(viewModel.isRunning)
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You → Partner (Live Microphone)")
                .font(.headline)

            laneCard(
                title: "Your partial speech",
                text: viewModel.sourcePartialText,
                color: .blue.opacity(0.15)
            )

            laneCard(
                title: "Partner partial translation",
                text: viewModel.targetPartialText,
                color: .green.opacity(0.15)
            )
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var partnerInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Partner → You (Simulated Input)")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Type partner speech in partner language", text: $viewModel.partnerInputText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.isRunning)

                Button("Translate") {
                    viewModel.submitPartnerText()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isRunning)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var finalSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final Segments")
                .font(.headline)

            Text("To Partner (iPhone playback target)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            segmentList(viewModel.toPartnerSegments)

            Text("To You (Earphones playback target)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            segmentList(viewModel.toMeSegments)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics")
                .font(.headline)

            keyValueLine("Status", viewModel.statusMessage)
            keyValueLine("Active route", viewModel.audioRouteSummary)
            keyValueLine("To Partner output", viewModel.partnerPlaybackSummary)
            keyValueLine("To You output", viewModel.mePlaybackSummary)
            keyValueLine("Dual-route active", viewModel.isDualRouteActive ? "Yes" : "No")

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func keyValueLine(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func segmentList(_ segments: [InterpretedSegment]) -> some View {
        Group {
            if segments.isEmpty {
                Text("No segments yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(segments) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(segment.sourceText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(segment.targetText)
                            .font(.body)

                        Text("MT latency: \(segment.translationLatencyMs) ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Playback route: \(segment.playbackRouteLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func laneCard(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(text.isEmpty ? "…" : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
