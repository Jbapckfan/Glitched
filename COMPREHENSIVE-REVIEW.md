# Glitched — Comprehensive Code Review

**Reviewed by:** Claude Opus 4.6 (3 parallel review agents + direct analysis) + Codex (OpenAI o4-mini)
**Date:** 2026-04-06
**Codebase:** 80,835 lines of Swift across ~70 files (20,996 in Scenes, 2,032 in Core, 3,917 in Characters/UI/DeviceIntegration/App/Input)
**Stack:** Swift 5 / SpriteKit / SwiftUI / CoreMotion / AVFoundation / Speech / LocalAuthentication

---

## Executive Summary

Glitched is a creatively exceptional iOS puzzle platformer where each of its 30 levels uses a different device sensor or OS feature as the core game mechanic. The concept is genuinely original, the visual language is cohesive, and the character design is surprisingly polished for code-drawn art.

The codebase has been through multiple review cycles (visible in commit history: Codex review, Gemini review, 20+ FIX numbers). This has produced solid fundamentals. However, **several critical gameplay-breaking bugs remain**, and there are architectural patterns that will cause issues as the project matures.

**Overall Grade: B+** (Concept: A+, Visual Design: A, Core Architecture: B+, Bug-Free: C, Testing: F)

---

## Critical Bugs (Ship-Blockers)

### 1. World 1 -> World 2 Transition is Broken
**Files:** `Level10_TimeTravel.swift:1084`, `LevelFactory.swift:35`

Level 10's `transitionToNextLevel()` creates `LevelID(world: .world2, index: 1)`, but LevelFactory maps World 2 starting at index **11**, not 1. The factory falls through to the default case and loads BootSequenceScene. Players who complete World 1 will be dumped back to the boot screen.

```swift
// Level10_TimeTravel.swift:1084 — WRONG
let nextLevel = LevelID(world: .world2, index: 1)

// Should be:
let nextLevel = LevelID(world: .world2, index: 11)
```

### 2. VoiceCommandManager Posts Undefined Event (Compile Error)
**Files:** `VoiceCommandManager.swift:51`, `GameInputEvent.swift`

`VoiceCommandManager.reportMicDenied()` posts `.voiceCommandMicDenied`, but this case does not exist in the `GameInputEvent` enum. This is a compile-time error that should prevent the project from building.

### 3. Level 18 (App Switcher) Wires Wrong Device Manager
**File:** `Level18_AppSwitcher.swift:29`

Configures `.appBackgrounding` instead of `.appSwitcher`, which activates `BackgroundTimeManager` instead of `AppSwitcherManager`. The scene listens for `.appSwitcherPeeked` events that will never arrive because the correct producer is never enabled.

### 4. Level 20 (Meta Finale) Core Mechanic Never Activates
**File:** `Level20_MetaFinale.swift:81`

Configures `.appBackgrounding` but the reinstall mechanic lives in `ReinstallManager` under `.appDeletion`. The scene waits for `.appReinstallDetected` at line ~600, but `ReinstallManager` is never activated. The finale's signature mechanic is non-functional.

---

## High-Priority Issues

### 5. Missing NSMotionUsageDescription — CRASH on Device
**File:** `Info.plist`

`ShakeUndoManager` uses `CMMotionManager.startAccelerometerUpdates()`, which requires `NSMotionUsageDescription` in Info.plist since iOS 14. This key is missing. **The app will crash on device when Level 16 (Shake Undo) activates.**

### 6. ProgressManager World Boundary Unlock Bug
**File:** `ProgressManager.swift:58-63`

`isUnlocked()` only checks levels within `highestWorld` up to `highestLevelIndex + 1`. Completing the last level of World 1 (index 10) does not unlock World 2 Level 11 in a menu-driven flow because the world transition logic doesn't account for cross-world boundaries.

### 7. Level 19 Advertises Non-Existent Proximity Manager
**File:** `Level19_FaceID.swift:40`

Configures `[.faceID, .proximity]`, but `DeviceManagerCoordinator` has no proximity manager. The `.proximity` mechanic has no producer, creating a dead code path.

### 8. Dual Scene Transition Ownership
**Files:** `GameRootView.swift:94-103` + multiple scene files

Scene transitions happen in two places:
- `SpriteKitContainer.updateUIView()` re-presents when `GameState.currentLevelID` changes
- Individual scenes call `view.presentScene()` directly (Level 1, 10, 11, 30, etc.)

This split ownership risks duplicate or racing transitions and makes lifecycle behavior unpredictable.

### 9. Proxy-Based Device Integrations with False Positives
- `FocusModeManager` infers Focus Mode from notification settings (conflates permanent permission state with temporary Focus)
- `NetworkManager` infers Airplane Mode from "no WiFi + no cellular + no path" (false-positives on any offline condition)
- These make puzzle logic unreliable — players could get stuck or accidentally solve puzzles

---

## Architecture Review

### Strengths

**File Organization: A**
- Clear separation: `Core/`, `Scenes/`, `DeviceIntegration/`, `UI/`, `Characters/`, `App/`, `Input/`
- One file per level, one file per device manager — easy to navigate
- Consistent naming conventions throughout

**BaseLevelScene Pattern: A**
- Clean template method pattern: `configureScene()`, `runIntroSequence()`, `updatePlaying()`, `handleGameInput()`
- Automatic juice effects on success/failure via `playVictoryEffects()`/`playDeathEffects()`
- Combine subscription cleanup in `willMove(from:)` — proper lifecycle management
- Dynamic difficulty hints after 30 seconds of no progress (FIX #13)

**InputEventBus: A-**
- `@MainActor` annotation for thread safety (FIX #19)
- Clean Combine `PassthroughSubject` pattern
- Last-event caching for late subscribers (FIX #2)
- One concern: `lastEvent(forKey:)` and `clearLastEvents()` appear unused — dead code

**DeviceManager Protocol + Coordinator: A-**
- Clean protocol: `supportedMechanics`, `activate()`, `deactivate()`
- Registry-based coordinator with lifecycle management (activate on foreground, deactivate on background)
- 29 implementations, all following the same pattern

**GameInputEvent Enum: A**
- Comprehensive event vocabulary (~40 cases across 4 worlds)
- Associated values carry relevant data (not just flags)
- Well-organized by world theme

### Weaknesses

**Singleton Overload: C+**
Every core system is a singleton: `GameState.shared`, `InputEventBus.shared`, `JuiceManager.shared`, `HapticManager.shared`, `AudioManager.shared`, `ProgressManager.shared`, `AccessibilityManager.shared`, `ScreenRecordingDetector.shared`, `DeviceManagerCoordinator.shared`, plus all 29 DeviceManagers. This works for a solo project but makes testing and scene isolation very difficult.

**ProgressManager Loads from Disk Every Call: C**
`ProgressManager.load()` decodes from UserDefaults on every invocation. `isUnlocked()` and `markCompleted()` both call `load()` — meaning every unlock check hits disk, decodes JSON, and allocates. Should cache the loaded progress and invalidate on writes.

**No Unit Tests: F**
Zero test files. Zero XCTest imports. The project has protocols for `GameStateProviding` and `DeviceManagerCoordinating` (FIX #1), showing intent to test, but no tests exist. For a project with 30 device integration mechanics, this is a significant risk.

---

## SpriteKit Usage

### Strengths
- Physics categories are well-defined and consistently applied (`PhysicsCategory` struct)
- Delta time clamping in `BaseLevelScene.update()` prevents physics jumps after backgrounding
- Camera-space touch conversion in `PlayerController` is correct (FIX #3) — a common SpriteKit pitfall handled well
- Custom shader scanlines in `BaseLevelScene.addScanlines()` — nice aesthetic touch

### Concerns
- **Node accumulation**: Particle effects (`ParticleFactory`) use `removeFromParent()` after duration, but rapid death/respawn cycles could create node buildup before cleanup fires
- **SKShapeNode heavy**: The entire character, UI, and level geometry uses `SKShapeNode` extensively. While this enables the clean line-art aesthetic, `SKShapeNode` is known to be less performant than `SKSpriteNode` at scale. Profile on older devices.
- **Implicitly unwrapped optional**: `gameCamera: SKCameraNode!` in BaseLevelScene — could crash if accessed before `didMove(to:)`

---

## Visual Design & Character

### BitCharacter: A+
The astronaut character is remarkably polished for procedural art:
- Multi-part articulated body (helmet, visor, torso, arms, legs, backpack, antenna)
- Walking animation with leg swing, arm counter-swing, body bob
- Three-tier glitch effect system (subtle, medium, intense) with weighted random scheduling
- RGB ghost copies and static noise overlays for intense glitches
- Jump/land squash-and-stretch
- Chromatic aberration offset during glitches

### JuiceManager: A
Comprehensive game-feel system:
- Screen shake with dampening curve
- Slow motion / freeze frame
- Flash, vignette pulse, chromatic aberration
- Death sequence with pixel fragmentation and respawn reassembly
- Pop text for feedback

### Visual Consistency: A
- Monochrome black/white with cyan accent throughout
- Consistent `VisualConstants` for colors, fonts, sizes
- Every level maintains the same aesthetic language
- SpriteKit + SwiftUI bridge handled cleanly

---

## Device Integration Quality

### Best Implementations
- **MotionManager**: Real CoreMotion gyroscope with proper lifecycle
- **AuthenticationManager**: Fresh `LAContext` per evaluation (FIX #8), proper error handling
- **NotificationGameManager**: Scoped cleanup to game-owned notification identifiers
- **BrightnessManager**: `CADisplayLink` polling — the only reliable way to track system brightness

### Problematic Implementations
- **FocusModeManager**: Infers from notification authorization — unreliable proxy
- **NetworkManager**: Airplane mode detection by absence of connectivity — false positives likely
- **AirDropManager / Level 28**: Overlapping share logic between scene and manager
- **VoiceCommandManager**: Undefined event case, dead code path on mic denial
- **StorageSpaceManager**: Polling timer for storage space — expensive and unnecessary for game pace

### Performance Concern: Polling Timers
Multiple managers use repeating timers:
- `BrightnessManager` — CADisplayLink (60fps)
- `ClipboardManager` — Timer
- `BatteryLevelManager` — Timer
- `StorageSpaceManager` — Timer
- `TimeOfDayManager` — Timer

Only brightness truly needs high-frequency polling. Others could use longer intervals or event-driven approaches.

---

## Level Design Patterns

### Consistency: A-
All 30 levels follow the same structural pattern:
1. `configureScene()` sets levelID, physics, registers mechanics, builds geometry
2. `setupBackground()` + `setupLevelTitle()` for visual setup
3. `buildLevel()` creates platforms, hazards, exit door
4. `setupBit()` creates player character
5. `handleGameInput()` responds to device events
6. `onLevelSucceeded()` marks progress and transitions

### Creative Highlights
- **Level 0 (Boot)**: Terminal boot sequence with digital rain — sets the tone perfectly
- **Level 1 (Header)**: Drag the HUD level title down to create a bridge — breaks the fourth wall immediately
- **Level 8 (Dark Mode)**: Dual world visible only in dark/light modes
- **Level 10 (Time Travel)**: Background the app and "years pass" — tree grows
- **Level 12 (Clipboard)**: Copy a password to solve a terminal puzzle
- **Level 20 (Meta Finale)**: "Delete and reinstall" the app
- **Level 29 (The Lie)**: "No gimmick" — then reveals the real exit was behind you
- **Level 30 (Credits)**: Walk on developer credits, dodge literal bugs

### Concern: Later Worlds Drift from Real Mechanics
By World 4, some levels are more theatrical than mechanically truthful. The AirDrop level uses a share sheet, not actual AirDrop. The Locale level simulates language changes rather than reading real settings. This is a design choice, not a bug, but it weakens the "device as controller" premise.

---

## Security & Privacy

### Good
- Proper `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSFaceIDUsageDescription` in Info.plist
- Permission preflight screen on first launch (FIX #12)
- Clipboard access scoped to active gameplay
- Screen recording detection with playful easter egg — not blocking

### Concerns
- **KeychainHelper** in Level 20 ignores `SecItemAdd` status codes — silently fails
- **Clipboard reading** (Level 12) could inadvertently capture sensitive data — should validate/discard immediately after checking
- **Device name** (Level 23) reads the user's device name and displays it in-game — privacy-sensitive, should note in permissions preflight
- **ReinstallManager** relies on Keychain persistence across reinstalls — behavior varies by iOS version

---

## Additional Findings from Deep Review

### AudioManager Bugs (Core Agent)
- **Phase accumulation bug**: `playJump()`, `playDeath()`, and `playDanger()` calculate frequency per-sample but use `Float(frame) / sampleRate` for phase — producing incorrect pitch sweeps. Should accumulate phase: `phase += (frequency / sampleRate) * 2 * .pi`
- **`playGlitch()` generates pure noise**: Random frequency per sample means no sine continuity — functionally identical to noise
- **No audio session interruption handling**: Phone calls/Siri will interrupt the engine with no recovery — App Store review concern
- **Unbounded player node allocation**: `playBuffer()` creates a new `AVAudioPlayerNode` per call with no pooling or cap

### JuiceManager Issues (Core Agent)
- **`originalCameraPosition` goes stale**: Captured once in `setScene()` — if camera follows player, shake resets to wrong position. Should capture at start of each `shake()` call
- **`DispatchQueue.main.asyncAfter` fires during pause**: `slowMotion()` and `freezeFrame()` use asyncAfter, which isn't tied to scene time. Restores normal speed even when scene is paused. Use `SKAction.wait` instead

### BitCharacter Bug (App/UI Agent)
- **`playIntenseGlitch` head position bug**: Line 486 sets `head.position = CGPoint(x: 22 + offsetY, ...)` — the Y-base-position (22) is accidentally in the X coordinate, causing the head to fly off to the right during intense glitches

### DeviceNameManager iOS 16+ Issue (App/UI Agent)
- `UIDevice.current.name` returns the model name (e.g., "iPhone") instead of the user-assigned name on iOS 16+ unless granted local network/Contacts permission. **Level 23's personalization mechanic will not work on modern iOS.**

### Missing iCloud Entitlement (App/UI Agent)
- `ReinstallManager` uses `NSUbiquitousKeyValueStore` which requires the `com.apple.developer.ubiquity-kvstore-identifier` entitlement. No `.entitlements` file is referenced in `project.yml`. **Level 20's reinstall detection will silently fail on device.**

### Massive Code Duplication (Scenes Agent)
~200 lines of boilerplate are copy-pasted across all 30 level files:
- `createPlatform(at:size:)` — ~20-30 lines, repeated in 25+ levels
- `createExitDoor(at:)` — ~40-50 lines, repeated in 20+ levels
- Touch handler forwarding (4 methods) — identical in every level
- Physics contact delegate (2 methods) — identical in every level
- `handleDeath()` / `handleExit()` / `transitionToNextLevel()` — identical except next level ID

Extracting shared code into `BaseLevelScene` would cut the Scenes layer from ~21,000 to ~14,000 lines.

### Level 2 Missing Death Guard (Scenes Agent)
`Level2_Wind.swift:723` — `handleDeath()` is the only level missing `guard GameState.shared.levelState == .playing else { return }`, allowing multiple simultaneous death sequences.

### Unused Hint System (Scenes Agent)
The FIX #13 hint system (`hintText()` + `resetProgressTimer()`) exists in `BaseLevelScene` but **zero levels** override `hintText()` or call `resetProgressTimer()`. Every player sees the generic "Try using your device's features..." hint. Each level should provide a specific hint.

### Level 5 Strong Capture in Haptic Chain (Scenes Agent)
`Level5_Charging.swift:654-659` — `startRiseHaptics()` inner function references `isPlugAnimating` without `[weak self]` capture in recursive `DispatchQueue.main.asyncAfter` chain.

### project.yml Issues (App/UI Agent)
- `SWIFT_VERSION: "5.0"` should be `5.9` or `6.0`
- `DEVELOPMENT_TEAM: ""` will fail code signing on device
- Info.plist `info` block has both `path` and `properties` — ambiguous precedence
- Missing `NSFaceIDUsageDescription` in project.yml properties (present in actual Info.plist file)

---

## Recommendations (Priority Order)

### Must Fix Before Ship (Crash/Broken Gameplay)
1. **Add `NSMotionUsageDescription` to Info.plist** — crash on device without it
2. **Fix World 1->2 transition**: change `index: 1` to `index: 11` in Level10_TimeTravel.swift:1084
3. **Add `.voiceCommandMicDenied` case** to `GameInputEvent` enum — compile error
4. **Fix Level 18 mechanic wiring**: configure `.appSwitcher` not `.appBackgrounding`
5. **Fix Level 20 mechanic wiring**: configure `.appDeletion` not `.appBackgrounding`
6. **Add iCloud KV store entitlement** for Level 20's reinstall detection
7. **Fix `ProgressManager.isUnlocked()`** to handle cross-world boundaries

### Should Fix (Correctness/Quality)
8. Fix `JuiceManager.originalCameraPosition` stale issue — capture at shake time
9. Replace `DispatchQueue.main.asyncAfter` with `SKAction.wait` in JuiceManager
10. Fix AudioManager phase accumulation bugs in `playJump`/`playDeath`/`playDanger`
11. Add audio session interruption handling (App Store concern)
12. Fix `playIntenseGlitch` head position bug (X/Y swap at line 486)
13. Add death guard to Level 2's `handleDeath()`
14. Consolidate scene transition ownership to one path
15. Remove unused `.proximity` mechanic from Level 19
16. Pool `AVAudioPlayerNode` instances instead of creating per-call

### Should Improve (Architecture/Performance)
17. Extract ~200 lines of duplicated code per level into `BaseLevelScene`
18. Override `hintText()` in each level for useful per-level hints
19. Cache `ProgressManager.load()` instead of deserializing every call
20. Add `@MainActor` to `GameState` for `@Published` thread safety
21. Profile SKShapeNode count on older devices — consider texture caching
22. Reduce polling frequency on timer-based managers
23. Add unit tests for at minimum `ProgressManager`, `GameState`, `InputEventBus`, `LevelFactory`

### Low Priority (Polish)
24. Replace `UIScreen.main` (deprecated iOS 16+) with window-scene-based access
25. Update `SWIFT_VERSION` from `5.0` to current
26. Add `deinit` observer removal in `KeyboardState`
27. Handle `DeviceNameManager` iOS 16+ name restriction for Level 23
28. Use `@ObservedObject` instead of `@StateObject` for singletons in GameRootView

---

---

## Review Sources

### Codex (o4-mini) — Full-Auto Review
Read every Swift file, attempted xcodebuild. Identified all 4 critical wiring bugs, progression boundary issue, proxy-based detection unreliability, dual scene transition ownership, and error handling inconsistency. Called out Level 8's global state mutation and AirDrop/share mechanic overlap.

> "Glitched is creatively strong and visually coherent. The strongest code is the handcrafted SpriteKit presentation and the better-integrated device managers; the weakest code is the coordination layer between levels, progression, and device mechanics."

### Claude Agent 1 — Core Layer Review (13 files)
Deep-dived into AudioManager, JuiceManager, HapticManager, ParticleFactory, GameState, InputEventBus, ProgressManager. Found audio synthesis phase bugs, JuiceManager stale camera position, audio session interruption gap, unbounded player node allocation, and ParticleFactory memory concerns.

### Claude Agent 2 — Scenes Layer Review (31 files)
Read all 31 scene files. Found massive code duplication (~200 lines per level), Level 2 missing death guard, unused hint system, Level 0 timer leak, Level 5 strong capture. Assessed each level's mechanic quality and provided the sensor integration quality table.

### Claude Agent 3 — App/UI/DeviceIntegration/Characters Review (17 files + config)
Found the critical missing `NSMotionUsageDescription` (crash risk), missing iCloud entitlement (Level 20 broken), `DeviceNameManager` iOS 16+ restriction, BitCharacter head position bug, project.yml issues, and `@StateObject` antipattern.

---

## Final Assessment

**The concept is A+.** Using the iPhone's own sensors and OS features as puzzle mechanics is genuinely innovative. The 30-level arc across 4 thematic worlds (Hardware Awakening -> Control Surface -> Data Corruption -> Reality Break) builds beautifully. The fourth-wall breaks (drag the HUD, delete the app, "no gimmick" fake-out) are the kind of creative design that gets featured on the App Store.

**The art direction is A.** The monochrome line-art aesthetic with cyan accent is distinctive and cohesive. BitCharacter is one of the best procedurally-drawn game characters in SpriteKit — the astronaut with three-tier glitch effects, walking animations, and chromatic aberration is polished beyond what code-drawn art typically achieves.

**The architecture is B+.** Clean file organization, consistent patterns, well-designed event bus and device manager protocol. Weakened by singleton overload and code duplication.

**The bug-free score is C.** 7 ship-blocking issues remain (1 crash, 2 compile errors, 4 broken mechanics). The singleton-heavy architecture and zero test coverage make these wiring errors predictable.

**Fix the 7 ship-blockers, add `NSMotionUsageDescription`, set up the iCloud entitlement, and this is ready for TestFlight.**
