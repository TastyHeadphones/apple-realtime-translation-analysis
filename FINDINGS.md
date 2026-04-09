# FINDINGS

## Scope
- [Confirmed] Analysis stayed focused on `Translate.app` and directly related translation runtime components.
- [Confirmed] The current shipped demo uses a local third-party stack (`SwiftWhisper`, `llama.swift`, `AVFAudio`, `SwiftUI`) rather than Apple Intelligence.
- [Confirmed] No private API calls, no entitlements abuse, and no proprietary code reconstruction were used.

## Translate Runtime Signals
- [Confirmed] `Translate.app` binary is FairPlay-protected and very small (thin-client profile).
- [Confirmed] System components relevant to interpretation include `Translation.framework`, `TranslationDaemon.framework`, `TranslationInference.framework`, `SpeechTranslation.framework`, and `translationd` Mach services.
- [Confirmed] Symbols indicate streaming primitives, result buffering, and finality semantics.

## Streaming/Incremental Evidence
- [Confirmed] Public iOS 26.4 API exposes `TranslationSession.Strategy.lowLatency` and `.highFidelity`.
- [Confirmed] Speech pipeline APIs support progressive transcription (`SpeechTranscriber` with `.timeIndexedProgressiveTranscription`) and per-result `isFinal` semantics.
- [Likely] Apple live interpretation behavior is built around incremental ASR + stabilization + incremental translation + optional spoken output queueing.

## AirPods Requirement (User Observation)
- [Confirmed] User-observed product gating to newer AirPods models is plausible for Apple’s shipping UX constraints.
- [Confirmed] iOS 26 public audio APIs include `AVAudioSessionModeDualRoute` (iOS 26.2+) and Bluetooth microphone capability surfaces, enabling simultaneous built-in speaker + supported headset/Bluetooth duplex routes without private API.
- [Likely] Product gating to specific AirPods models is tied to route quality/latency and Bluetooth capability profiles (for example high-quality recording and far-field support), not a hidden translation API.
- [Hypothesis] Apple may apply additional product-side eligibility heuristics above these public capabilities.
- [Unknown] Exact internal gating logic for AirPods model checks and route-policy thresholds.

## Practical Reproduction Outcome
- [Likely] The local-model demo reproduces the core live experience pattern:
  - continuous microphone ingest
  - progressive source transcript updates (`You -> Partner`)
  - throttled partial translation updates
  - finalized segment translation with latency capture
  - second direction translation path (`Partner -> You`) via simulated partner input
  - route-targeted spoken output intents:
    - partner lane -> iPhone built-in output target
    - user lane -> headset/earphone output target
- [Likely] This architecture is the best public-API approximation of Apple live translation behavior without private internals.
