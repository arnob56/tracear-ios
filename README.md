# TraceAR — Free, Offline AR Drawing Assistant for iOS

TraceAR helps you trace photos and practice guides onto physical paper using ARKit surface anchoring, or sketch directly on screen. It runs **100% offline** with **no ads, no subscriptions, no third-party dependencies, and no analytics**.

## Requirements

- **Xcode**: 15.0 or later (Swift 5.9+)
- **Minimum iOS**: 16.0
- **Target Hardware**: iPhone 12 or newer recommended for AR tracing (60 fps on A14 OLED). The 2D Sketch Pad and unit tests also run in the iOS Simulator.

## Project Structure

```text
TraceAR/
├── TraceAR.xcodeproj/                # Ready-to-open Xcode project (App + Unit Test targets)
├── TraceAR/
│   ├── Info.plist                    # Portrait lock + Camera & Photos purpose strings
│   ├── Assets.xcassets/              # Universal 1024x1024 AppIcon & Light/Dark AccentColor
│   ├── App/
│   │   ├── TraceARApp.swift          # App entry & portrait orientation delegate
│   │   └── ContentView.swift         # Mode switcher, onboarding trigger, scenePhase lifecycle
│   ├── Models/
│   │   ├── TraceConfiguration.swift  # Opacity/filter config, cache keys, sample shape catalog
│   │   ├── ARTrackingStatus.swift    # Tracking quality & hysteresis-backed StabilityMonitor
│   │   ├── AppErrorState.swift       # Friendly error descriptors & recovery actions
│   │   └── SketchModels.swift        # 2D stroke models & undo/redo SketchCanvasViewModel
│   ├── Services/
│   │   ├── TraceImageProcessor.swift # Metal-backed Core Image edge/grayscale/invert pipeline
│   │   ├── SampleShapeGenerator.swift# 6 offline vector drawing guides
│   │   ├── SketchRenderer.swift      # Smooth quadratic curve & transparent-ink PNG renderer
│   │   ├── PhotoLibraryService.swift # Add-only Photos authorization & export helpers
│   │   └── HapticsManager.swift      # Place, lock, and status haptics
│   ├── AR/
│   │   ├── ARSessionViewModel.swift  # AR state, permissions, async filter task, snapshots
│   │   └── ARTraceViewContainer.swift# 60 fps ARSCNView, gestures, screen-aligned anchoring
│   └── Views/
│       ├── OnboardingView.swift      # 3-screen skippable setup guide
│       ├── ARTraceScreen.swift       # One-handed AR HUD, lock, opacity, filter chips
│       ├── ReferencePickerSheet.swift# PhotosPicker, clipboard paste, sample shapes
│       ├── SketchPadScreen.swift     # On-screen canvas (pencil/eraser, 3 sizes, 6 colors)
│       ├── SettingsSheet.swift       # Keep-screen-awake, replay onboarding, session reset
│       ├── ErrorBannerView.swift     # Actionable error & re-anchor banners
│       └── ShareSheet.swift          # Native UIActivityViewController wrapper
└── TraceARTests/
    ├── SketchCanvasStateTests.swift  # Undo/redo, clear recovery, memory warning trim tests
    ├── SketchExportTests.swift       # PNG export, eraser isolation, sample generator tests
    └── TraceStateAndFilterTests.swift# StabilityMonitor, Core Image filters, transform tests
```

## Xcode Setup, Signing & Build Steps

1. **Copy to a Mac** with Xcode 15+ installed and double-click `TraceAR.xcodeproj`.
2. In the Xcode Project Navigator, select the root **TraceAR** project -> **Signing & Capabilities** tab.
3. Select the **TraceAR** target:
   - Check **Automatically manage signing**.
   - Choose your **Team** (a free Personal Apple ID team works).
   - If `com.tracear.app` is already claimed on Apple's provisioning servers, change **Bundle Identifier** to a unique string (for example, `com.<yourname>.tracear`).
4. Connect your **iPhone 12** via USB (or Wi-Fi debugging) and unlock the phone.
   - If using a free Personal Team for the first time on the device, open **Settings -> General -> VPN & Device Management** on your iPhone after installation and tap **Trust** on your developer certificate.
5. Select your iPhone 12 as the run destination and press **Cmd + R** to build and run.

## Running Unit Tests

1. Select any **iPhone Simulator** (e.g., iPhone 15 / iPhone 16) or connected iPhone destination in Xcode.
2. Press **Cmd + U** (or run from Terminal):
   ```bash
   xcodebuild test \
     -project TraceAR.xcodeproj \
     -scheme TraceAR \
     -destination 'platform=iOS Simulator,name=iPhone 15'
   ```
