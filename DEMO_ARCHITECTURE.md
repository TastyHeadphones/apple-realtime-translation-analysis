# Demo Architecture

## Goal

Reproduce Apple-style live interpretation on iPhone without Apple Intelligence dependencies.

## Current architecture

### Capture
- `LocalSpeechStreamingService`
- `AVAudioEngine` microphone tap
- resamples to 16 kHz mono float PCM
- buffers audio in rolling windows

### Speech-to-text
- `SwiftWhisper`
- selected Whisper model:
  - `ggml-base-q5_1.bin` for the fastest preset
  - `ggml-small-q5_1.bin` for the balanced and quality presets
- emits partial transcript updates every few hundred milliseconds
- finalizes on speech pause

### Translation
- `LocalTranslationService`
- local GGUF model loaded through `llama.swift`
- selected model:
  - `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`
  - `Qwen2.5-0.5B-Instruct-Q6_K.gguf`
- streams translated text token by token
- uses a translation prompt that only asks for the target language output

### Orchestration
- `RealtimeInterpreterViewModel`
- throttles partial translation requests
- keeps partial and final states separate
- preserves segment history and latency timing

### Output
- `RoutedSpeechOutputService`
- `AVSpeechSynthesizer` for optional translated speech
- route-aware playback for phone speaker vs earphones

## Why this design

- Small enough to run on an iPhone
- Downloadable in preset bundles instead of raw model management
- Incremental enough to feel simultaneous
- Easier to maintain than a single huge end-to-end model path

## Known limitations

- Whisper chunking is not perfect streaming ASR
- Translation quality depends on the selected GGUF model
- TTS is still system-based, not a local neural TTS model

