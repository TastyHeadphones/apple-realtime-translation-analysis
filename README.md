# apple-realtime-translation-analysis

Research and demo implementation for Apple-like live translation behavior using public iOS 26 APIs.

## Deliverables
- `RESEARCH.md`
- `FINDINGS.md`
- `DEMO_ARCHITECTURE.md`
- `IMPLEMENTATION_PLAN.md`
- `TODO.md`
- `RUN.md`
- `ios26_demo/` (Swift package demo source)

## Demo Tech Stack
- `Translation` framework (`TranslationSession`, `preferredStrategy`)
- `Speech` framework (`SpeechAnalyzer`, `SpeechTranscriber` progressive mode)
- `AVFAudio` (`AVAudioEngine`, `AVSpeechSynthesizer`)
- `SwiftUI`
- Route-aware conversation outputs (`AVAudioSessionModeDualRoute`, `AVSpeechSynthesizer.outputChannels`)

## Build Verification
```bash
cd ios26_demo
xcodebuild -scheme RealtimeInterpretationDemo -destination 'generic/platform=iOS Simulator' build
```
