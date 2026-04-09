# RUN

## Prerequisites

- Xcode 26.4+
- iOS 26.4 simulator or device
- Microphone permission
- Enough free disk space for the selected preset

## Build

```bash
./scripts/bootstrap_llama_runtime.sh
cd ios26_host_app
xcodegen generate
xcodebuild -project RealtimeInterpretationHost.xcodeproj -scheme RealtimeInterpretationHost -destination 'generic/platform=iOS Simulator' build
```

## Launch

```bash
./scripts/bootstrap_llama_runtime.sh
cd ios26_host_app
open RealtimeInterpretationHost.xcodeproj
```

Scheme:
- `RealtimeInterpretationHost`

## How to use

1. Pick a preset in the app.
2. Download the preset.
3. Choose source and target languages.
4. Tap `Start Live Translation`.

## Behavior

- Live speech is chunked and transcribed locally.
- Partial text updates appear before segment finalization.
- Translation updates stream from the local LLM.
- Optional TTS uses the iPhone’s built-in speech synthesizer.

## Troubleshooting

- If the app says the preset is missing, tap `Download Selected Preset`.
- If Xcode cannot find `llama-cpp.xcframework`, rerun `./scripts/bootstrap_llama_runtime.sh`.
- If the build complains about packages, rerun `xcodegen generate`.
- If the mic starts but no text appears, check the microphone permission and speak continuously for a few seconds.
