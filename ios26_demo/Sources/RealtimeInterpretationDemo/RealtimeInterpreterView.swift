import SwiftUI

@available(iOS 26.4, *)
public struct RealtimeInterpreterView: View {
    @StateObject private var viewModel: RealtimeInterpreterViewModel

    public init(viewModel: @autoclosure @escaping () -> RealtimeInterpreterViewModel = RealtimeInterpreterViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.11, blue: 0.20),
                        Color(red: 0.05, green: 0.24, blue: 0.30),
                        Color(red: 0.09, green: 0.13, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        headerSection
                        configurationSection
                        liveSection
                        partnerInputSection
                        finalSections
                        diagnosticsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("Live Translation")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                controlSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Interpreter")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(viewModel.isDualRouteActive ? "Dual Route" : "Single Route")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.isDualRouteActive ? Color.green : Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
            }

            Text("AirPods lane for you, iPhone lane for partner speech.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(14)
        .cardBackground(cornerRadius: 20, tint: .white.opacity(0.12))
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Conversation Setup", symbol: "gearshape.2")

            HStack(spacing: 8) {
                TextField("Your locale (en-US)", text: $viewModel.config.sourceLocaleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.secondary)

                TextField("Partner locale (es-ES)", text: $viewModel.config.targetLocaleIdentifier)
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
                Text("Partial update throttle")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.config.partialTranslationThrottleMs) ms")
                    .font(.subheadline.monospacedDigit())
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
        .padding(14)
        .cardBackground(cornerRadius: 20)
        .disabled(viewModel.isRunning)
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("You → Partner (Live Mic)", symbol: "waveform")

            laneCard(
                title: "Partial Speech",
                text: viewModel.sourcePartialText,
                tint: Color.blue.opacity(0.15)
            )

            laneCard(
                title: "Partial Translation",
                text: viewModel.targetPartialText,
                tint: Color.green.opacity(0.16)
            )
        }
        .padding(14)
        .cardBackground(cornerRadius: 20)
    }

    private var partnerInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Partner → You (Text Sim)", symbol: "earbuds")

            TextField("Type partner speech in partner language", text: $viewModel.partnerInputText)
                .textFieldStyle(.roundedBorder)
                .disabled(!viewModel.isRunning)

            Button {
                viewModel.submitPartnerText()
            } label: {
                Label("Translate To You", systemImage: "arrow.down.left.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isRunning)
        }
        .padding(14)
        .cardBackground(cornerRadius: 20)
    }

    private var finalSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Final Segments", symbol: "text.quote")

            ViewThatFits {
                HStack(alignment: .top, spacing: 10) {
                    segmentColumn(
                        title: "To Partner (Phone)",
                        segments: viewModel.toPartnerSegments,
                        tint: Color.blue.opacity(0.10)
                    )
                    segmentColumn(
                        title: "To You (Earphones)",
                        segments: viewModel.toMeSegments,
                        tint: Color.green.opacity(0.12)
                    )
                }

                VStack(spacing: 10) {
                    segmentColumn(
                        title: "To Partner (Phone)",
                        segments: viewModel.toPartnerSegments,
                        tint: Color.blue.opacity(0.10)
                    )
                    segmentColumn(
                        title: "To You (Earphones)",
                        segments: viewModel.toMeSegments,
                        tint: Color.green.opacity(0.12)
                    )
                }
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 20)
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Diagnostics", symbol: "waveform.path.ecg")

            keyValueLine("Status", viewModel.statusMessage)
            keyValueLine("Active route", viewModel.audioRouteSummary)
            keyValueLine("To Partner output", viewModel.partnerPlaybackSummary)
            keyValueLine("To You output", viewModel.mePlaybackSummary)
            keyValueLine("Dual-route active", viewModel.isDualRouteActive ? "Yes" : "No")

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.92))
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 20)
    }

    private var controlSection: some View {
        VStack(spacing: 10) {
            HStack {
                Label(viewModel.statusMessage, systemImage: viewModel.isRunning ? "dot.radiowaves.left.and.right" : "pause.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(viewModel.config.strategy == .lowLatency ? "Low Latency" : "High Fidelity")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .foregroundStyle(.white)

            Button {
                if viewModel.isRunning {
                    viewModel.stop()
                } else {
                    viewModel.start()
                }
            } label: {
                Label(viewModel.isRunning ? "Stop Live Translation" : "Start Live Translation", systemImage: viewModel.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRunning ? .red : .green)
        }
        .padding(12)
        .cardBackground(cornerRadius: 18, tint: .white.opacity(0.12))
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

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title)
                .font(.headline)
            Spacer()
        }
        .foregroundStyle(.primary)
    }

    private func segmentColumn(title: String, segments: [InterpretedSegment], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if segments.isEmpty {
                Text("No finalized segments.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(segments.suffix(5))) { segment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(segment.sourceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(segment.targetText)
                                .font(.body)

                            HStack {
                                Text("\(segment.translationLatencyMs) ms")
                                Spacer()
                                Text(segment.playbackRouteLabel)
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func laneCard(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(text.isEmpty ? "…" : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

@available(iOS 26.4, *)
private extension View {
    func cardBackground(cornerRadius: CGFloat, tint: Color = Color(.systemBackground).opacity(0.92)) -> some View {
        background(tint, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
