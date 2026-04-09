# RUN

## Prerequisites
- Xcode 26.4+ with iOS 26.4 SDK
- iOS deployment target 26.4
- Microphone permission
- Installed translation/speech assets for selected language pair on device

## Build Check (already verified)
```bash
cd ios26_demo
xcodebuild -scheme RealtimeInterpretationDemo -destination 'generic/platform=iOS Simulator' build
```

## Use in an iOS App
This repo provides a Swift package library target, not a standalone app target.

1. Open your iOS app project in Xcode.
2. Add local package dependency:
- Path: `ios26_demo` (from this repository root)
3. Import and embed the view:
```swift
import SwiftUI
import RealtimeInterpretationDemo

@main
struct DemoHostApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(iOS 26.4, *) {
                RealtimeInterpreterView()
            } else {
                Text("Requires iOS 26.4+")
            }
        }
    }
}
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
