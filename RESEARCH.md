# Phase 1 Research: Apple Translate Package Real-Time Interpretation

## Scope
- [Confirmed] Primary artifact inspected: `Translate.app`.
- [Confirmed] Additional runtime components inspected only when directly required to explain Translate runtime behavior: `Translation*`, `SpeechTranslation`, launchd entries, and translation asset catalogs under `/System/Library`.
- [Confirmed] Analysis method: lawful static inspection (Mach-O metadata, dyld exports/imports, plist/asset metadata, localization tables).

## Evidence Constraints
- [Confirmed] `Translate.app/Translate` is FairPlay-protected (`cryptid 1`) and symbol-stripped; direct function-level internals are not readable from this package alone.
- [Confirmed] `Translate.app/Translate` is very small (~91 KB), indicating a thin client that delegates core runtime behavior to system frameworks/daemons.
- [Confirmed] The app bundle includes no embedded translation/ASR/TTS models.
- [Unknown] Exact internal control flow inside the iOS app executable cannot be reconstructed from this artifact.

## 1) Components Most Relevant to Real-Time Interpretation

### App/Process Layer
- [Confirmed] `Translate.app` (iPhoneOS bundle) + watch companion app.
- [Confirmed] `translationd` launch agent: `/System/Library/LaunchAgents/com.apple.translationd.plist`.
- [Confirmed] `translationd` Mach services: `com.apple.translationd` and `com.apple.translation.text`.

### Core Translation Runtime
- [Confirmed] Public framework surface: `Translation.framework` (`TranslationSession`, `Strategy.lowLatency`, `Strategy.highFidelity`, async batch response).
- [Confirmed] Private orchestration frameworks: `TranslationDaemon.framework`, `TranslationInference.framework`, `SpeechTranslation.framework`, `TranslationAPISupport.framework`, `TranslationUI.framework`, `TranslationUIServices.framework`.

### Speech/Audio + Endpointing
- [Confirmed] `TranslationDaemon` imports `EmbeddedAcousticRecognition` classes: `_EAREndpointer`, `_EAREndpointFeatures`, `_EARSpeechRecognizer`, `EARCaesuraSilencePosteriorGenerator`, `EMTStablePrefixState`.
- [Confirmed] `TranslationDaemon` imports audio capture/playback primitives (`AudioQueue*`, `AVAudio*`, `AudioConverter*`) and `SNAudioStreamAnalyzer`.

### TTS and Output Audio
- [Confirmed] `TranslationDaemon` imports `SiriTTSService` classes (`SiriTTSDaemonSession`, `SiriTTSSynthesisRequest`, `SiriTTSSynthesisVoice`, `TTSAsset`).
- [Confirmed] `SpeechTranslation` exports support translated audio output (`preferredOutputAudioFormat`, `omitTranslatedAudio`, generated audio metadata).

### Model and Asset Layer
- [Confirmed] Speech translation asset catalog exists: `/System/Library/AssetsV2/com_apple_MobileAsset_SpeechTranslationAssets7/com_apple_MobileAsset_SpeechTranslationAssets7.xml`.
- [Confirmed] Catalog includes ASR, MT, phrasebook (PB), LID, endpointer, config assets.
- [Confirmed] MT asset names include many `partial` variants (50/64 MT assets marked `partial-*`).
- [Confirmed] Unified asset aliases for translate/messages/public API include model keys for MT base + draft + tokenizer + alignment + phrasebook.

### Policy/Feature Flags
- [Confirmed] Translate feature flags include `onDeviceFirst`, `btiSubSentenceSegmentation`, `translationSemanticSegmentation`, `asset_services_general_asr`, `ai_adapter_inference`, `lowConfidenceLID`.
- [Confirmed] Localization strings include on-device mode policy and speech-session limits (e.g., ongoing speech translation, speech duration exceeded).

## 2) Most Likely Pipeline Behind Apple-Like Real-Time Simultaneous Translation

### Observed Evidence
- [Confirmed] Streaming primitives/classes exist: `_LTStreamingInput`, `_LTStreamingOutput`, `_LTStreamingSpeakableOutput`, `_LTStreamingUtteranceTranslator`, `_LTSpeechTranslationResultsBuffer`.
- [Confirmed] Speech translation delegate callbacks are incremental by design (did produce outputs; finish callback) in `SpeechTranslation` exports.
- [Confirmed] Result objects explicitly carry finality: `STTranscriptionResult(text,isFinal)` and `STTranslationResult(...,isFinal)`.
- [Confirmed] Stabilization-related symbols exist: `_LTStabilizationTranslationResult`, `EMTStablePrefixState`.

### Inference
- [Likely] Audio capture and chunking happen continuously, with endpoint/caesura detection driving segmentation boundaries.
- [Likely] Incremental ASR hypotheses are stabilized by prefix logic before translation commits.
- [Likely] Translation runs incrementally over segments/spans/tokens, not only whole utterance batch.
- [Likely] Spoken output is generated per committed translated segment, with audio queue scheduling for low perceived delay.
- [Likely] `translationd` acts as orchestrator, while framework clients (app/UI/API) consume XPC-backed translation services.

### End-to-End Pipeline (Most likely)
1. [Likely] Microphone frames -> stream analyzer + endpointer/caesura.
2. [Likely] Incremental ASR emits partial hypotheses + confidence/stability signals.
3. [Likely] Prefix stabilizer commits sub-sentence spans.
4. [Likely] Streaming MT translates committed spans with alignment metadata.
5. [Likely] UI updates partial then final text for each span.
6. [Likely] Optional TTS synthesizes translated spans and enqueues playback.
7. [Likely] Feedback loop adjusts segmentation/latency strategy (`lowLatency` vs `highFidelity`).

## 3) Strongest Signals of Streaming or Incremental Processing
- [Confirmed] `TranslationSession.Strategy.lowLatency` and `highFidelity` in public API.
- [Confirmed] Async batch response stream (`BatchResponse.AsyncSequence`) in public API.
- [Confirmed] `STTranscriptionResult(...isFinal)` and `STTranslationResult(...isFinal)` symbols.
- [Confirmed] Streaming object model (`_LTStreamingInput/Output/SpeakableOutput/UtteranceTranslator`).
- [Confirmed] Stabilization symbols (`_LTStabilizationTranslationResult`, `EMTStablePrefixState`).
- [Confirmed] Endpoint/silence/caesura classes (`_EAREndpointer`, `EARCaesuraSilencePosteriorGenerator`).
- [Confirmed] Translation daemon buffering class (`_LTSpeechTranslationResultsBuffer`).
- [Confirmed] Model artifact naming with `partial` MT variants in speech-translation asset catalog.
- [Confirmed] Feature flags explicitly mentioning sub-sentence and semantic segmentation.

## 4) Confirmed vs Likely vs Hypothesis vs Unknown

### Confirmed
- [Confirmed] Translate app binary is protected and thin-client-like.
- [Confirmed] Runtime stack includes `Translation`, `TranslationDaemon`, `TranslationInference`, `SpeechTranslation`.
- [Confirmed] Dedicated daemon (`translationd`) exposes translation Mach services.
- [Confirmed] Symbols and assets indicate ASR + streaming MT + alignment + phrasebook + TTS + endpointing.

### Likely
- [Likely] Apple-like interpretation mode is implemented as an incremental speech->translate->speak loop with stabilization gates.
- [Likely] Daemon-side orchestration coordinates ASR/MT/TTS with on-device-first behavior and optional online fallback.
- [Likely] The latency profile is dominated by segment commit thresholds and TTS chunk scheduling.

### Hypothesis
- [Hypothesis] Apple may dynamically choose between offline engine and AI-adapter engine per language pair/task hint/device condition.
- [Hypothesis] "Draft" MT models are used for faster partials, then refined by fuller passes.

### Unknown
- [Unknown] Exact internal heuristics for commit thresholds, VAD tuning, and re-write suppression.
- [Unknown] Exact queueing policy for overlapping ASR/MT/TTS stages and barge-in behavior.
- [Unknown] Exact online fallback trigger conditions in interpretation mode for each locale pair.

## 5) Best Demo Architecture Recommendation

### Architecture
- [Likely] Best tradeoff is a modular streaming pipeline with explicit state boundaries:
  - Audio Ingress: microphone frame stream (20–40 ms chunks).
  - VAD/Endpoint: speech activity + pause/turn detector.
  - Streaming ASR: partial + final emissions.
  - Stabilizer: commit stable prefix/window, suppress flicker.
  - Incremental MT: segment-level translation + optional revision of trailing segment.
  - Renderer: partial/final transcript + partial/final translation lanes.
  - Optional TTS: synthesize only committed translation chunks; queue audio with interrupt policy.

### Why this is the best practical tradeoff
- [Confirmed] Apple stack exposes low-latency strategy, streaming results, and finality semantics.
- [Likely] Mimicking those semantics (not exact proprietary internals) is what drives Apple-like UX.
- [Likely] This architecture maximizes perceived simultaneity while keeping implementation maintainable and debuggable.
- [Likely] It allows independent tuning of latency/quality at ASR, stabilizer, and MT stages.

## Validation Steps for Weak-Evidence Areas
- [Likely] Measure end-to-end latency budget per stage (audio->ASR partial, ASR final->MT partial/final, MT final->TTS playback).
- [Likely] Run A/B on commit heuristics (stable-prefix length, pause threshold, max wait timeout).
- [Likely] Instrument correction rate (partial-to-final rewrite distance) and user-visible flicker.
- [Likely] Validate on-device-only mode behavior by forcing offline assets and disconnecting network.
