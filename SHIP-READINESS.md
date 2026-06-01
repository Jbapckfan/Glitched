# Glitched — Ship-Readiness Audit

> Audit date: 2026-06-01. main @ `987e9b9`, builds clean (1 warning).
> Method: 11 parallel audit streams (6 level clusters + app-shell/save/IAP,
> privacy/compliance, manager teardown ×2, accessibility fallback matrix),
> synthesized into one ranked blocker list. 85 findings (14 raw P0 → ~13
> distinct, 31 P1, 40 P2). READ-ONLY audit; no code changed to produce this.

## VERDICT: NOT READY — ~13 distinct P0 ship-blockers

**One systemic root cause dominates.** `AccessibilityManager.needsFallbackUI`
(`AccessibilityManager.swift:83-86`) returns false unless a level called
`forceHardwareFallback(for:)` or Hardware-Free Mode is on — and **only 3 levels
ever call it** (L1 dragHUD, L2 mic, L4 volume). Every other hardware-gated level
shows **no fallback button on a default Simulator run**, so its mechanic can
never fire and the exit is unreachable. **App Store reviewers run the
Simulator** → near-certain rejection across ~12 levels. Fixing this one thing
(auto-force fallbacks under `#if targetEnvironment(simulator)`) resolves ~9 of
the P0/P1 findings at once and is the dependency for verifying every level fix.

**Correction to an earlier alarm:** the L8 "100pt single-jump softlock" is
**REFUTED**. `light1` is an intermediate foothold (start→dark1 +50 → light1 +100
→ dark2 +150 → door +200); the level IS completable by toggling appearance at
each 50pt hop. L8's geometry concern is **P1** (fragile/undersignposted forced
toggle), not P0. L8's real P0 is the same systemic missing-fallback.

## P0 ship-blockers (deduped, with owner)

| # | Blocker | Location | Owner |
|---|---------|----------|-------|
| 1 | **Systemic:** only 3 levels call `forceHardwareFallback` → ~12 levels uncompletable on default Simulator (L3, L5, L6, L8, L9, L10, L17, L19, L31, L32 confirmed) | `AccessibilityManager.swift:78-90` | **shared-coordinated** |
| 2 | **L9 Orientation** unwinnable on device: Info.plist is portrait-only, the rotate premise can never render | `Info.plist:35-38`, `project.yml:43-44` | **shared-coordinated** (product decision) |
| 3 | L9: no sim fallback gating (compounds #2) | `Level9_Orientation.swift:82-83` | mbp |
| 4 | **L17 AirplaneMode** uncompletable on iPad: fixed-X platforms vs `size.width` exit → ~699pt gap | `Level17_AirplaneMode.swift:99-126` | **mac-mini** |
| 5 | **L18 AppSwitcher** exit unreachable on iPad: fixed-X stones vs `size.width` exit → ~637pt gap | `Level18_AppSwitcher.swift:81-88` | **mac-mini** |
| 6 | L5 Charging: no fallback → plug never rises on sim | `Level5_Charging.swift:47-48` | mbp |
| 7 | L3 Static: no fallback → lasers stay armed on sim | `Level3_Static.swift:70-73` | mbp |
| 8 | L6 Brightness: no fallback → UV platforms never solid on sim | `Level6_Brightness.swift:73-97` | mbp |
| 9 | L8 DarkMode: in-scene toggle + overlay both gated off on sim | `Level8_DarkMode.swift:104-105,1206-1209` | mbp |
| 10 | **L10 TimeTravel** uncompletable sim/HFM: `.appBackgrounding` has NO overlay button at all | `Level10_TimeTravel.swift:58-59`; `GameRootView.swift:190-279` | **shared-coordinated** |
| 11 | L19 FaceID: proximity-only solve with `.proximity` button suppressed on sim | `Level19_FaceID.swift:340-351,543-551` | **mac-mini** |
| 12 | **L32 MultiTouch:** `.multiTouch` overlay event has NO `handleGameInput` consumer; sim caps at 2 touches | `Level32_MultiTouch.swift` (no handleGameInput); `GameRootView.swift:274-276` | **mac-mini** |

(Most of #3,#6,#7,#8,#9,#11 collapse into #1 if the systemic fix auto-forces
fallbacks for every registered mechanic on the Simulator. #4/#5 (iPad geometry),
#10 (missing overlay button), #12 (missing consumer), and #2 (Info.plist) are
independent and need their own fixes.)

## P1 (serious — fix before ship; deduped)

- **L8** toggle-per-platform solve is fragile/undersignposted (100pt gap if you stay one mode) — `Level8_DarkMode.swift:340,374,381,392,399` — mbp
- **L4** hidden escalating wake-threshold = uncommunicated time limit, can kill a stationary player — `Level4_Volume.swift:854-861` — mbp
- **L11** faux-notification only on DENIED; overlay id `'fallback'` never matches `pendingNotificationId` → dead unlock — `Level11_Notification.swift:424-467`; `GameRootView.swift:222-224` — mac-mini
- **L12** overlay posts `"GLITCH"` but level needs `"GLITCH3D"` → dead HFM unlock — `Level12_Clipboard.swift:21`; `GameRootView.swift:226` — shared-coordinated
- **L13** WiFi wall-skip margin ~0.5pt, unverified at iPad displayScale 1.25 — `Level13_WiFi.swift:123-137` — mac-mini
- **L14** FocusModeManager 0.5s poll can override manual toggle → unfair death — `Level14_FocusMode.swift:226-255,397-415` — mac-mini
- **L16** shake undo uninvokable on sim/HFM (no button, threshold ~never fires) — `Level16_ShakeUndo.swift:48-64` — mac-mini
- **L18** no `.appSwitcher` overlay button + mechanic/event mismatch (separate from #5) — `Level18_AppSwitcher.swift:36,388,393` — shared-coordinated
- **L19** registers `[.faceID,.proximity]` but overlay has only `.proximity`, no `.faceID` — `GameRootView.swift:240-241` — shared-coordinated
- **L21** overlay posts only `"open"`; BRIDGE/FLY unreachable via overlay (in-scene fallback saves it) — `GameRootView.swift:249` — shared-coordinated
- **L23** no `.deviceName` overlay button; HFM deactivates the manager — `GameRootView.swift`; `DeviceManagerCoordinator.swift:98` — shared-coordinated
- **L27** VoiceOver-as-primary user-trap; in-scene reveal is DEBUG-only; only the 3-death hint saves release — `Level27_VoiceOver.swift:32,213-233,310-348` — mac-mini
- **L28** `.airdrop` fallback posts `"GLITCH"` ≠ random doorCode → dead unlock — `Level28_AirDrop.swift:55-58,519-523`; `GameRootView.swift:265-267` — shared-coordinated
- **L31** Flashlight: no fallback + single fixed pitch lights only ceiling not floor pits — `Level31_Flashlight.swift:76-77,1173-1213` — mac-mini
- **L25** no `.timeOfDay` overlay button (in-scene CYCLE keeps it winnable — verify) — shared-coordinated
- **PrivacyInfo.xcprivacy** declares SystemBootTime (35F9.1) but no boot-time API is used → inaccurate manifest — `PrivacyInfo.xcprivacy:21-28` — shared-coordinated
- **MicrophoneManager** activate/deactivate race can leave the mic hot — `MicrophoneManager.swift:18-39,63` — shared-coordinated
- **ProgressManager.save()** silently drops the write on encode failure; no `synchronize()` → latent progress loss — `ProgressManager.swift:113-117` — either

## What is NOT a blocker (good news)
- Build is clean. App shell, IAP, Game Center surfaced **no** P0s; save path has only a latent P1.
- Privacy manifest present + all 4 usage strings present (mic/FaceID/motion/speech). (Verify NSCamera if torch needs it — flagged in P1 review.)
- L13/L16/L19/L20/L21/L23/L24/L29 completability fixes from prior passes hold.

## Work division (dependency-ordered)

**Phase 1 — systemic shared-file pass (MBP owns, BLOCKING dependency, do FIRST):**
1. Central auto-`forceHardwareFallback` for every registered mechanic under `#if targetEnvironment(simulator)` (`AccessibilityManager` + a `BaseLevelScene` hook). Resolves P0 #1,#3,#6,#7,#8,#9,#11 and several P1s at once.
2. `GameRootView` overlay completeness: add missing buttons (`.appBackgrounding` → `.timePassageSimulated`, `.deviceName`, `.appSwitcher`, `.faceID`, `.timeOfDay`); fix payloads (L12 `"GLITCH3D"`, L28 live doorCode, L21 voice).
3. `Info.plist` L9 landscape decision (add landscape + handle `didChangeSize`, OR pull L9) — **product call needed**.
4. `PrivacyInfo.xcprivacy` remove SystemBootTime; `MicrophoneManager` teardown race; `ProgressManager.save()` hardening.

**Phase 2 — Mac Mini lane (L11+ level-internal, parallelizable; geometry items need NO dependency on Phase 1):**
- L17 + L18: convert to the L3 `courseX`/`courseLen` centered course (fixes the iPad gaps — independent of fallback).
- L32: add `handleGameInput` consumer for the multitouch fallback + reduce required simultaneous touches.
- L19: proximity fallback surface; L31: two-state tilt fallback; L13 wall margin; L14 DND poll latch; L16 in-scene undo; L11 fallback-id; L27 death-hint primary.

**Phase 3 — verify:** rebuild iPhone+iPad, re-run completability traces per level, regression sweep.
