# DEMO_ARCHITECTURE

## Goal
Approximate Apple-like live translation UX with public iOS 26.4 APIs and low perceived latency.

## Runtime Pipeline
1. Audio ingress
- `AVAudioEngine` captures live microphone PCM buffers.
- Buffers are streamed into `SpeechAnalyzer` as `AnalyzerInput`.

2. Incremental ASR
- `SpeechTranscriber(locale:preset:)` with `.timeIndexedProgressiveTranscription` emits progressive transcript results.
- Each ASR result is treated as partial or final via `isFinal`.

3. Stabilization
- `TranscriptStabilizer` tracks committed transcript text and computes a stable tail delta.
- Partial text remains in a live lane; final text is committed per segment.

4. Translation
- `TranslationService` wraps `TranslationSession(installedSource:target:preferredStrategy:)`.
- `preferredStrategy` is configurable (`lowLatency` vs `highFidelity`).
- Partial translation is throttled to reduce flicker and compute churn.
- Two directional translation sessions:
  - `You -> Partner` (microphone transcript direction)
  - `Partner -> You` (simulated partner text direction)
- Finalized source segments are translated and recorded with per-segment MT latency.

5. Output rendering
- SwiftUI view shows:
  - `You -> Partner` partial lane
  - `Partner -> You` simulated input lane
  - finalized segment lists per direction (source, target, latency, playback-route label)
  - diagnostics/status

6. Optional speech output
- Final translated segments are synthesized via `AVSpeechSynthesizer`.
- Audio routing intent is split by direction:
  - to partner: iPhone built-in speaker target
  - to user: headset/earphone target
- Routing uses:
  - `AVAudioSession` dual-route configuration when available (`.multiRoute + .dualRoute`)
  - `AVSpeechSynthesizer.outputChannels` bound to route channel descriptions

## Components
- `SpeechStreamingService`: microphone + progressive transcription stream.
- `TranscriptStabilizer`: partial/final state transitions.
- `TranslationService`: translation-session lifecycle and calls.
- `RoutedSpeechOutputService`: route introspection and per-lane speech output targeting.
- `RealtimeInterpreterViewModel`: orchestration, throttling, cancellation, dual-direction translation, segment bookkeeping.
- `RealtimeInterpreterView`: demo UI.

## Why this architecture is the best tradeoff
- Uses only public APIs available in iOS 26.4.
- Preserves the core semantics observed in Apple’s stack: progressive updates, finality, latency strategy selection.
- Keeps stage boundaries explicit for tuning and observability.
- Avoids private runtime assumptions while still matching the perceived “simultaneous” UX pattern.

## Non-goals
- No private API invocation.
- No reverse-engineered proprietary algorithms.
- No hardware-gated behavior spoofing.
