# RUN

## Prerequisites
- Xcode 26.4+ with iOS 26.4 SDK
- iOS deployment target 26.4
- Microphone permission
- Installed translation/speech assets for selected language pair on device
- `xcodegen` (for regenerating the host app project)

## Build Check (already verified)
```bash
cd ios26_demo
xcodebuild -scheme RealtimeInterpretationDemo -destination 'generic/platform=iOS Simulator' build
```

## Open and Run the Host App
This repo now includes a runnable iOS app project at `ios26_host_app/`.

```bash
cd ios26_host_app
xcodegen generate
open RealtimeInterpretationHost.xcodeproj
```

Xcode scheme: `RealtimeInterpretationHost`

## CLI Build for Host App
```bash
cd ios26_host_app
xcodegen generate
xcodebuild -project RealtimeInterpretationHost.xcodeproj -scheme RealtimeInterpretationHost -destination 'generic/platform=iOS Simulator' build
```

## Build Without Xcode UI (direct from repo root)
```bash
xcodebuild -project ios26_host_app/RealtimeInterpretationHost.xcodeproj -scheme RealtimeInterpretationHost -destination 'generic/platform=iOS Simulator' build
```

## Runtime Notes
- Start with `lowLatency` strategy for simultaneous feel.
- Use `highFidelity` when translation quality is more important than immediacy.
- Partial translation throttle defaults to `350ms`; tune this for UX smoothness.
- Current UI flow:
  - microphone drives `You -> Partner`
  - text box simulates `Partner -> You`

## AirPods / Audio Route Notes
- The demo attempts dual-route routing via public API:
  - `AVAudioSessionCategoryMultiRoute` + `AVAudioSessionModeDualRoute` (iOS 26.2+)
  - fallback to `PlayAndRecord` when dual-route is unavailable
- For production-like behavior, test route latency and duplex quality on:
  - built-in mic/speaker
  - wired headset
  - supported newer AirPods models
- Diagnostics panel exposes:
  - active route
  - playback target route for `to partner`
  - playback target route for `to me`
  - dual-route active state
