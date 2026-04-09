# Implementation Plan

## Completed

1. Replaced the Apple Translate / Apple Intelligence pipeline.
2. Added local model presets with download-on-demand.
3. Wired live microphone capture to local Whisper transcription.
4. Wired partial and final translation to a local GGUF LLM.
5. Updated the SwiftUI demo to expose model selection and download progress.
6. Regenerated the host app project from `project.yml`.

## Next

1. Verify the app builds cleanly in Xcode.
2. Tune the Whisper windowing thresholds on a real device.
3. Measure latency for each preset.
4. Optionally add a local TTS model if you want the spoken output fully offline.

