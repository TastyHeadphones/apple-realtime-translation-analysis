# apple-realtime-translation-analysis

An iOS demo that reproduces Apple-style live translation with a fully local pipeline:

- Whisper for streaming speech-to-text
- a small local GGUF LLM for translation
- route-aware speech output
- preset downloads for fast, balanced, or higher-quality behavior

## What the app does

- Captures live microphone audio
- Produces incremental transcription updates
- Translates partial and final segments in near real time
- Optionally speaks translated output through the built-in route manager
- Lets the user choose a preset before downloading models

## Local presets

- `Realtime`
  - Whisper Base Q5
  - Qwen 0.5B Q4
  - Smallest download, fastest feel
- `Balanced`
  - Whisper Small Q5
  - Qwen 0.5B Q4
  - Recommended default
- `Quality`
  - Whisper Small Q5
  - Qwen 0.5B Q6
  - Better translation quality, larger download

## Languages

Supported conversation languages:
- English (US)
- Japanese
- Chinese (Mandarin)

## Build

```bash
./scripts/bootstrap_llama_runtime.sh
cd ios26_host_app
xcodegen generate
xcodebuild -project RealtimeInterpretationHost.xcodeproj -scheme RealtimeInterpretationHost -destination 'generic/platform=iOS Simulator' build
```

## Run

```bash
./scripts/bootstrap_llama_runtime.sh
cd ios26_host_app
xcodegen generate
open RealtimeInterpretationHost.xcodeproj
```

## Notes

- The first run downloads the selected preset into Application Support.
- The llama runtime is fetched separately by `./scripts/bootstrap_llama_runtime.sh`.
- The app does not require Apple Intelligence or Apple Translate assets.
- Microphone permission is still required.
