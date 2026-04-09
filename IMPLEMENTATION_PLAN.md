# IMPLEMENTATION_PLAN

## Phase 1: Research (Completed)
1. Inspect `Translate.app` package structure and binary metadata.
2. Inspect directly related runtime frameworks and daemons required to explain Translate behavior.
3. Gather static signals for streaming/incremental speech translation.
4. Distill confirmed vs inferred behaviors and recommend a reproducible architecture.

Status: Completed (`RESEARCH.md`).

## Phase 2: Demo Build (Completed)
1. Create iOS 26.4 Swift package (`ios26_demo`).
2. Implement streaming microphone + progressive ASR service.
3. Implement transcript stabilizer for partial/final transitions.
4. Implement translation wrappers using `TranslationSession` with strategy control for both conversation directions.
5. Implement orchestrating view model with:
- start/stop lifecycle
- partial translation throttling
- final segment translation and latency tracking
- directional playback targets (`to partner`, `to me`)
- optional TTS
6. Implement route-aware speech output service:
- dual-route audio session attempt (`AVAudioSessionModeDualRoute`) with fallback
- `AVSpeechSynthesizer.outputChannels` lane targeting
7. Implement SwiftUI demo screen.
8. Build-verify on iOS simulator toolchain.

Status: Completed (`xcodebuild` succeeded on 2026-04-09).

## Validation Plan (Next)
1. Run on physical iOS 26 device with microphone permission flow.
2. Measure latency per stage (ASR partial, ASR final, MT final, TTS start).
3. Tune throttling and segment commit heuristics for perceived simultaneity.
4. Compare external headset routes (including newer AirPods) vs built-in mic/speaker paths.
