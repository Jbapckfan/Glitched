# Glitched — App Store Readiness Audit

**Verdict: NOT-READY — 38/100**

_44-agent critical audit (34 per-level reviews + 9 cross-cutting dimensions), reviewing main + pending PR #2 (L7-10)._

## Would people pay?

The CORE PITCH is genuinely sellable — "your phone IS the controller" with a sharp, fourth-wall narrator is a real "show a friend" hook, and the free slice (L0-L10) front-loads enough novelty (drag the boot bar, blow on the mic, screenshot to freeze, flip dark mode that recolors your actual phone) to drive installs. But TODAY this is not a game people would be happy to pay for; it is a high-craft prototype with a beautiful surface stretched over a half-finished product. The honest problem is that the paid slice — the thing the fullgame IAP actually delivers — is where the wheels come off: roughly a third of Worlds 2-5 are mechanically hollow (the headline device "puzzle" is never required, or is auto-solved by a timer/cutscene, or is bypassable), and several are outright unwinnable (L5 plug-ride is a SpriteKit physics impossibility; L14 Focus locks the exit exactly when the level is safe; L18/L32 render their solution off-screen; L31's torch can't even be detected). Worse, the things a buyer evaluates are broken or missing: the paywall shows NO price, purchase/restore failures are swallowed silently, Game Center (the entire replay/retention layer) fires zero achievements and has no UI, and the devcommentary IAP is a non-purchasable ghost that will get the build REJECTED. The build also ships iPad-enabled (project.pbxproj TARGETED_DEVICE_FAMILY="1,2", overriding the stale project.yml), so ~28 hardcoded-iPhone-geometry levels softlock on iPad — meaning an iPad customer literally cannot finish the campaign they paid for. Verdict: a paying customer who clears the clever free levels and buys the IAP will hit a no-pause softlock, an unbeatable level, or a "felt like a tech demo" letdown within the first few paid levels and refund. Fix the ~8 P0s and the paid slice's hollow-mechanic levels and this becomes a 4-star premium curiosity; ship as-is and it earns refunds, 1-stars, and an App Review rejection.

## P0 — Ship Blockers (11)

1. onboarding/core-loop — No pause or exit inside any level — PauseMenuView is unreachable dead UI, so any unsolved device puzzle is a hard softlock
   - **Fix:** Add a persistent safe-area pause/back button to HUDLayer for ALL levels that calls GameState.shared.togglePause(); the menu already has RETURN_TO_MAP via showWorldMap(). Currently togglePause() is only invoked from the RESUME button INSIDE the already-open menu, so the player can never open it.
   - **Lane:** `UI/LevelHeaderHUD.swift (HUDLayer); App/GameRootView.swift:367; Core/GameState.swift:119`
2. monetization — devcommentary IAP is a non-purchasable ghost product (declared+loaded+shown LOCKED, no buy path, no gated content, can never unlock) — App Review rejection
   - **Fix:** Either ship real commentary content gated on isUnlocked(devCommentaryProductID) WITH a priced purchase button, or remove devCommentaryProductID from the products array and the Settings status row before submission. isUnlocked() hard-codes the test-unlock to fullGame only, so it can never be unlocked in any build.
   - **Lane:** `Core/StoreManager.swift:9,47,82; UI/SettingsView.swift:39`
3. monetization — Paywall never shows a price and swallows purchase/restore failures silently
   - **Fix:** Render store.product(for: fullGameProductID)?.displayPrice + a 'what you get (Worlds 2-5, Levels 11-33)' line on the UNLOCK button; disable it until the product resolves. Replace `_ = try? await store.purchase()` and print-only restore errors with user-facing alerts (distinguish userCancelled/pending from real failure; confirm 'restored' vs 'nothing to restore').
   - **Lane:** `UI/WorldMapView.swift:112-147,328-339; Core/StoreManager.swift:72-79`
4. compliance — Level 33 auto-fires SKStoreReviewController with no user action AND frames a review as a progression gate (Guideline 1.1.6 rejection)
   - **Fix:** Remove the automatic requestReview on the wait-it-out path (requestPostCompletionReviewIfNeeded, lines 1155-1163); only ever request a review from a direct user tap, once per completion. Reframe copy so the review is unambiguously optional and never gates the exit.
   - **Lane:** `Scenes/Level33_AppReview.swift:1142,1155-1163,876,881-884`
5. monetization/retention — Game Center is shipped but completely non-functional — zero achievement/score/world-completion reports anywhere, no leaderboard IDs, no GC UI entry point
   - **Fix:** Wire reportWorldCompleted into ProgressManager.markCompleted, report speedrun/no-hint/score off LevelStats, define+register leaderboard IDs, and add a GKGameCenterViewController button in Settings or the WorldMap header. If not finishing for launch, remove the entitlement rather than ship a dead retention layer.
   - **Lane:** `Core/GameCenterManager.swift:99-167 (no callers); App/GlitchedApp.swift:59`
6. device-ipad — Build ships iPad-enabled (project.pbxproj family '1,2') but ~28 levels hardcode ~390-430pt geometry, creating uncrossable gaps -> campaign unbeatable on iPad
   - **Fix:** Either set the app target's TARGETED_DEVICE_FAMILY to '1' for a clean iPhone-only launch (and delete the misleading dead iPad code), OR convert every non-responsive level to the L6/L9 size-relative pattern before shipping universal. Note: pbxproj (authoritative) = '1,2' overrides the stale project.yml='1', so the softlocks are LIVE, not latent.
   - **Lane:** `Glitched.xcodeproj/project.pbxproj:795,818; LevelFactory.swift:94; Levels 11/12/14/17/22/25/26/28 et al.`
7. completability — Level 5 (Charging) is built on a SpriteKit impossibility: a static body cannot carry the player, and the plug erupts up THROUGH the player from below — uncompletable via its own mechanic, and a passive cutscene even if fixed
   - **Fix:** Make the plug a kinematic mover and explicitly carry Bit by applying the plug's per-frame deltaY when grounded on it; redesign boarding so Bit is demonstrably standing on the plug before it rises; add real platforming agency during the ride.
   - **Lane:** `Scenes/Level5_Charging.swift:478,518-524,565-588,719-736`
8. completability — Level 14 (Focus) exit/freeze logic inverted — door is locked WHILE hazards are frozen, opens only when hazards move; plus DND detector never detects DND and manual toggle self-reverts in 0.5s
   - **Fix:** Invert the gate so the exit is PASSABLE while Focus is ON (walk out through frozen hazards). Suspend the 0.5s notification-proxy poll when a manual override is active. Reword instructions to point at the in-level DND button since notificationCenterSetting/alertSetting never reflect real Focus state.
   - **Lane:** `Scenes/Level14_FocusMode.swift:344-351,461-462; DeviceIntegration/FocusModeManager.swift:23-27,40-69`
9. completability — Level 32 (Multi-touch) renders all Section-3 plates off-screen (scene coords inside gameCamera) -> Group 3 unreachable, exit never reveals on EVERY device; plus 4+1-finger ergonomics impossible on phones and a dead fallback
   - **Fix:** Add plates/rings/lines/label directly to the scene OR recompute every camera-child position as a camera-local offset (subtract size/2). Reduce simultaneous-hold count to a realistic max and spread plates clear of the traversal path. Wire a working .multiTouch fallback (override handleGameInput + forceHardwareFallback).
   - **Lane:** `Scenes/Level32_MultiTouch.swift:271-336,417,459-471; App/GameRootView.swift:274-276`
10. completability — Level 10 (free finale) background-time event is clobbered before delta can be computed (tree never grows on device) and has no production fallback — unbeatable on the last FREE level
   - **Fix:** Stop BackgroundTimeManager.deactivate() from nil'ing backgroundTimestamp (preserve it across the background/foreground cycle), and add a release-build fallback button gated on needsFallbackUI(.appBackgrounding) that posts .timePassageSimulated(years:12).
   - **Lane:** `DeviceIntegration/BackgroundTimeManager.swift:34-61; Core/DeviceManagerCoordinator.swift:118-122; App/GameRootView.swift (missing .appBackgrounding case)`
11. completability/accessibility — Level 31 (Flashlight) torch cannot be detected as designed (torchMode read with no AVCaptureSession) and has NO fallback -> dark-cave softlock on device/simulator/iPad, with instructions invisible at start
   - **Fix:** Have FlashlightManager own a real AVCaptureSession+torch (and add NSCameraUsageDescription), OR redesign off a reliable signal; always call forceHardwareFallback(for:.flashlight) when torch unavailable so an on-screen control appears; move the instruction panel/title OUTSIDE the cropNode so onboarding is visible before the torch is on.
   - **Lane:** `DeviceIntegration/FlashlightManager.swift:61-64; Scenes/Level31_Flashlight.swift:76-77,902-906,1173-1198; Info.plist`

## P1 — Must-Fix for Paid Quality (14)

1. completability — Level 1 (free teaching level) iPad/simulator accessibility fallback spawns NO bridge -> unwinnable softlock, and the spike pit is jumpable on iPhone so the signature mechanic is fully bypassed on the very level meant to teach it
   - **Fix:** Make the .dragHUD fallback post a pit-CENTERED scene coordinate computed from live geometry (not the hardcoded (210,240)); widen the pit beyond Bit's ~184pt reach or raise the spikes so a jump clips the hazard, forcing the drag-the-header solution.
   - **Lane:** `App/GameRootView.swift:190-197; Scenes/Level1_Header.swift:24-25,377`
2. bug — Level 2 (free) bridge retracts in ~1s (not 'very slowly' as promised) and de-solidifies under the player -> death loop on a key free-slice charmer
   - **Fix:** Do not decay bridgeTargetWidth while there is no mic input; hold the full span 4-6s after a strong blow and use the gentle 5pt/s path as the only retract. When shrinking segments, never retract under the player's current X and call bit.setGrounded(false) if their X exceeds the new physics extent.
   - **Lane:** `Scenes/Level2_Wind.swift:378-409,786-802`
3. completability/clarity — Level 3 (free) inverse 4th-laser twist is never explained and the stuck-hint actively teaches the lethal behavior ('Make noise to turn static into a shield'); fallback is near-unbeatable and no simulator-fallback force
   - **Fix:** Make hintText stage-aware ('the dashed laser is INVERSE — go SILENT to pass it'), add an in-world SILENCE cue over laser 4, switch the fallback to a latched/toggle shield, and add the #if targetEnvironment(simulator) forceHardwareFallback(.microphone) block that Level 2 has.
   - **Lane:** `Scenes/Level3_Static.swift:63-82,401-413,628-640,742-745,854-856; App/GameRootView.swift:198-200`
4. fun/clarity — Level 9 (free capstone) crusher kills a reading player in 2.5s with zero grace while the rotate hint is gated 18s behind BaseLevelScene -> ~7 deaths before the game tells you the answer
   - **Fix:** Add a 1.5-2.0s armed-delay before the crusher creeps and widen the spawn margin so a still player survives 6-8s; surface the rotate clue on the FIRST death rather than at the 18s no-progress timer.
   - **Lane:** `Scenes/Level9_Orientation.swift:864,920-933,1100-1102; BaseLevelScene.swift:58`
5. polish — Off-screen juice: L0 fake-crash payoff + a ghost victory layer, and L29's signature reveal glitch/flash, render at scene.size/2 while the camera is elsewhere -> the game's marquee moments play where nobody can see them
   - **Fix:** Attach flash/glitch/vignette/popText/victory overlays to scene.camera at camera-local (0,0) (as the difficulty-hint panel already does), or override playVictoryEffects() per scene. Verify on iPad where the offset is largest.
   - **Lane:** `Core/JuiceManager.swift:91-96,163-184,197-221; Scenes/Level0_BootSequence.swift:176-177; Scenes/Level29_TheLie.swift:345-347; BaseLevelScene.swift:317-323`
6. spec/fun — Hollow paid mechanics: headline device feature is NOT required, auto-solved, or a cutscene across L11/L13/L16/L17/L20/L23/L24/L25/L29 — the IAP delivers tech demos, not puzzles
   - **Fix:** Per level: L11 schedule 2-3 notifications with one correct; L13 gate the exit on download completion; L16 make a missed jump unrecoverable without rewind + fix the static moving platform; L17 require an ON<->OFF cycle; L20/L23/L29 replace timer/auto triggers with a real player choice/race; L13/L24/L25 add traversal the device-state actually gates.
   - **Lane:** `Scenes/Level11_Notification.swift; Level13_WiFi.swift; Level16_ShakeUndo.swift; Level17_AirplaneMode.swift; Level20_MetaFinale.swift; Level23_DeviceName.swift; Level24_StorageSpace.swift; Level25_TimeOfDay.swift; Level29_TheLie.swift`
7. completability — Paid-level hardcoded-geometry softlocks even on iPhone widths in several levels (uncrossable gaps / jumpable gates) — L11/L12/L17/L22/L25/L26/L28 mix fixed climb x with size.width-anchored exits
   - **Fix:** Drive ALL x/y from size with guaranteed-jumpable spacing (<=~150pt gaps, rises <91pt apex), place doors/exits relative to the actual gap, and make 'locked' gates full-height barriers that can't be mantled. Re-verify on the 390/402/430 + iPad matrix.
   - **Lane:** `Scenes/Level11_Notification.swift:196-248; Level12_Clipboard.swift:72-128; Level17_AirplaneMode.swift:106-126; Level22_BatteryPercent.swift:100-137; Level25_TimeOfDay.swift:127-134; Level26_Locale.swift:113-141; Level28_AirDrop.swift:91-101`
8. accessibility — Hardware-gated-without-fallback on paid levels L19 (FaceID) and L26 (Locale) softlock on iPad / release builds (no .faceID overlay button; L26 fallback is #if DEBUG-only)
   - **Fix:** Add an accessibilityButton(for:.faceID) posting .faceIDResult(true) and an always-visible in-scene AUTHENTICATE button; for L26 ship the locale toggle in release or auto-forceHardwareFallback(.locale) on a timeout. iPads lack Face ID AND proximity, so the current proximity-only fallback dead-ends.
   - **Lane:** `Scenes/Level19_FaceID.swift:340-352; Scenes/Level26_Locale.swift:248-268; DeviceIntegration/LocaleManager.swift; App/GameRootView.swift:180-280`
9. completability/clarity — Level 7 (free) screenshot mechanic has no auto-fallback (unbeatable on simulator) and is too obscure for a conversion level -> App Review dead-end risk
   - **Fix:** In configureScene detect simulator / inability and call forceHardwareFallback(for:.screenshot) so the AccessibilityOverlay camera button appears automatically (mirror L2/L4); surface the screenshot instruction earlier with the Side+Volume-Up glyphs.
   - **Lane:** `Scenes/Level7_Screenshot.swift:86-87,104-123,1051-1053; DeviceIntegration/ScreenshotManager.swift:14-28`
10. accessibility — Two ACCESSIBILITY settings are dead/misleading: highContrastMode read nowhere, extendedHintTimers consumed nowhere, and reduceScreenShake only halves shake; system Reduce Motion / Dynamic Type never consulted
   - **Fix:** Wire extendedHintTimers into noProgressHintDelay and highContrastMode into rendering (or remove both toggles); make reduceScreenShake fully suppress shake; read UIAccessibility.isReduceMotionEnabled in JuiceManager and scale in-scene fonts by preferredContentSizeCategory.
   - **Lane:** `Core/ProgressManager.swift:4-8; UI/SettingsView.swift:21-24; Core/JuiceManager.swift:54,88; BaseLevelScene.swift:58`
11. narrative — Narrator identity is incoherent (avatar 'Bit' vs first-person 'I live in your phone' OS vs third-person 'BIT IS WAITING') and the L30 credits/finale fire 4 levels too early then load L31
   - **Fix:** Pick one canon (OS narrator piloting Bit) and establish it in L0 with one line; reorder so the emotional climax lands on L33, or recast L30's early credits as an intentional 'fake credits' gag. Stop setting glitched_game_complete at L30.
   - **Lane:** `Scenes/Level0_BootSequence.swift:367; Level11_Notification.swift:29; Level30_CreditsFinale.swift:406,448,522,525-528`
12. perf — Frame hitches at the exact 'is this premium?' moments: 8s ambient audio buffer synthesized on the main thread every world entry; 50-130 unbatched SKShapeNode physics particles per death/victory
   - **Fix:** Move makeAmbientBuffer off-main / pre-render and cache per world; cap particle counts (~40 confetti, ~12 fragments), drop physics bodies (categoryBitMask=0), and migrate to single SKEmitterNodes. Also guard audio play paths on engine.isRunning to avoid silent-audio-for-the-session.
   - **Lane:** `Core/AudioManager.swift:60-64,344-424,485; Core/ParticleFactory.swift:14-55,106-143; BaseLevelScene.swift:99,328-355`
13. visual/typography — Generic Helvetica titles (the 56pt GLITCHED + all 32 level titles) fight the intentional Menlo terminal voice; design-token system declared but unused (fonts hardcoded 255x)
   - **Fix:** Route every title through VisualConstants.Fonts.main (Menlo-Bold or a bespoke display face) and have all levels consume shared color/lineWidth tokens instead of redeclaring them, delivering the consistent token system the project rules require.
   - **Lane:** `Core/VisualConstants.swift:25-34; Scenes/Level0_BootSequence.swift:264; all 32 level title sites`
14. compliance — Info.plist declares NSMotionUsageDescription (unused API) and FocusModeManager makes a false hardware claim (real Focus/DND never detected)
   - **Fix:** Remove NSMotionUsageDescription (raw CMMotionManager doesn't require it); for L14 either present the Focus mechanic honestly as an in-game toggle or use INFocusStatusCenter with proper authorization. Reconcile the portrait-lock vs L9 'rotate' framing.
   - **Lane:** `Info.plist:27-28,33-38; DeviceIntegration/FocusModeManager.swift:40-57`

## P2 — Polish (12)

- [onboarding] L0 boot intro is unskippable (~12s) and re-runs on every replay/tutorial re-entry; gate the tap/drag tutorial on a one-time flag and add tap-to-skip
- [conversion] Free->paid moment is a silent bounce to the WorldMap after L10; intercept the world boundary with a focused 'World 1 complete — unlock the rest' upsell beat
- [conversion] Paywall copy miscounts the free slice ('WORLD 1 IS FREE' ignores Worlds 0+1 / L0-L10) and never teases locked worlds; show mechanic subtitles + level counts for Worlds 2-5
- [polish] Camera-roll spam on L7 retries and the unskippable ~17s L20 intro/crash theatre on every replay turn signature gags into annoyances
- [visual] Disabled CRT scanline shader (commented out), sub-perceptual 12-16% per-world atmosphere occluded by level backgrounds, and rainbow system-color confetti — paid Worlds 2-5 look identical to free World 1
- [bug] Pervasive grounded-on-de-solidify across L1/L2/L5/L7/L13/L14/L16/L19/L21/L22/L23/L26: setting a body's categoryBitMask/physicsBody under a standing player fires no didEnd, leaving isGrounded stuck true — add a shared de-solidify helper that calls setGrounded(false)
- [bug] Redundant double-nested DispatchQueue.main.async in BatteryManager/BatteryLevelManager/FocusModeManager/PowerModeManager/DeviceNameManager/TimeOfDayManager — collapse to a single hop
- [clarity] L22 'SIM DRAIN' dev-jargon button, L4 meaningless '???' warning, and L24 buried Settings-cache mechanic bypassed by an always-on button — name actions in player-facing copy and teach the real verb
- [polish] Dead code: L1 drawCables(), L2 drawHangingVibrationPickup(), unreachable world0 map cases, and the never-run SpriteKitContainer crossFade branch (occluded by .id() view rebuild)
- [device] HUD anchored to configure-time topSafeY in many levels with no didUpdateSafeArea() override; consolidate the two divergent safe-area accessor systems in BaseLevelScene
- [narrative] Two commentary lines scold the paying player ('THIS IS YOUR LIFE.', 'YOU SHOULD PROBABLY BE DOING SOMETHING ELSE') — redirect the bite at the OS/game, not the customer
- [narrative] Build one shared GlitchedNarrator presenter (consistent type scale, safe-area placement, glitch/typewriter reveal) — the voice that IS the product is currently bare fade labels, some at fontSize 8 / alpha 0.5 and easily missed

## Top Strengths

- The core conceit — 'your phone IS the controller' with a sharp, dry, fourth-wall OS narrator — is a genuine 'show a friend' hook and the strongest selling point; the boot sequence (L0), L8 dark-mode-recolors-your-phone, L7 screenshot-to-freeze, and the L29/L33 meta beats are the kind of moments that drive word-of-mouth
- 23 distinct, inventive device mechanics across 34 levels is real breadth no competitor offers; the macro difficulty curve (one isolated mechanic per free level, compounding in paid worlds, with meta/walking palette-cleansers) is well-conceived
- Stability and memory hygiene are genuinely good (readiness 4): no retain cycles, [weak self] everywhere, clean per-frame loops, clamped delta time, defensive audio startup — very unlikely to crash or leak across a full playthrough
- BitCharacter procedural art (three-tier glitch flicker, RGB-split slice-shift, physics-based squash/stretch, coyote-aware) and the JuiceManager toolkit are well above typical SpriteKit code-art; the line-art aesthetic is disciplined and avoids AI-slop
- The accessibility ARCHITECTURE (centralized manager, per-mechanic forceHardwareFallback, global hardware-free mode) is better than most indie iOS games — the pattern exists and is applied well in L14/L15/L21/L23/L25; the gap is finishing the job, not designing it
- StoreKit 2 plumbing is correct: clean free/paid gate at the World 1->2 boundary (canAccess single source of truth), Transaction.updates wired, iCloud-merged progress, restore present

## Biggest Risks

- App Review REJECTION is near-certain as-is: the non-purchasable devcommentary IAP (2.1), the price-less paywall (3.1.2), and the auto-firing review-gate finale (1.1.6) are each independent hard-reject triggers
- The paid slice — the thing the IAP delivers — is where the product is weakest: ~1/3 of Worlds 2-5 are hollow (mechanic not required / auto-solved / bypassable) and several are outright unwinnable, so a buyer hits a 'felt like a tech demo' or unbeatable-level refund within the first few paid levels
- iPad customers literally cannot finish the campaign they paid for: the authoritative pbxproj ships family '1,2' while ~28 levels hardcode iPhone geometry into uncrossable gaps — a guaranteed refund/1-star 'unbeatable level' scenario in the paid worlds
- No pause/exit means any device-puzzle a player can't or won't perform (won't enable VoiceOver, declines Face ID, can't blow on the mic, is on a mount) is a force-quit-only softlock — and free-slice softlocks kill conversion before the IAP decision
- Zero retention layer: Game Center fires nothing and has no UI, no leaderboards, no replay incentive — a 34-level 'premium' game with no completion tracking reads as a tech demo and caps perceived value
- Silent purchase/restore failures + no shown price manufacture '1-star: I paid and nothing happened' reviews even from players who clear the free slice and want to buy

## Weakest Levels

- Level 5 (Charging) — ship:1 — uncompletable via its own mechanic (static body can't carry the player; plug erupts through the player from below) and a passive cutscene even if fixed. Do not ship.
- Level 14 (Focus Mode) — ship:1 — unwinnable: exit is locked exactly when the level is safe, DND detector never detects DND, manual toggle self-reverts in 0.5s, iPad softlock.
- Level 32 (Multi-touch) — ship:1 — hard-softlocked on all devices (Section-3 plates render off-screen), physically impossible 4+1-finger ergonomics, dead accessibility fallback. Clearly never run on a device.
- Level 31 (Flashlight) — ship:1 — torch can't be detected as designed, no fallback, instructions invisible at start, ceiling hazards literally can't hit you; dark-cave softlock by default.
- Level 27 (VoiceOver) — ship:1 — mechanically self-defeating (enabling real VoiceOver kills the touch controls the level requires) and the iPhone geometry collapses the gap into a blind-walkable slab; no toggle-free fallback.
- Level 18 (App Switcher) — ship:1 — iPad softlock, the advertised primary solve event is never delivered (dead code), the freeze fires backwards relative to the gesture, no fallback.
- Level 11 (Notifications) — ship:2 — the gateway to the PAID tier is a one-tap no-puzzle (every notification hardcoded correct, only one ever shown) that softlocks if you follow its own 'leave the app' instruction; uncompletable on iPad.
- Level 28 (AirDrop) — ship:2 — a ceremonial non-puzzle (code stays visible, keyboard contains only the answer), unbeatable on iPad, dead accessibility fallback.
- Level 23 (Device Name) — ship:2 — a scripted cutscene masquerading as a puzzle (doors open on timers, doppelganger never competes) whose personalization hook resolves to 'HELLO, IPHONE' on iOS 16+.
- Level 24 (Storage Space) — ship:2 — flat-floor-plus-one-button tech demo whose real device mechanic (clear cache from Settings) is undiscoverable and bypassed by its own always-on button.

## Per-World Notes

WORLD 0 (free, L0): Charming on-brand cold open; the fake-crash payoff and a ghost victory layer render off-screen (camera-at-origin vs effects-at-size/2). Unskippable ~12s intro punishes replay. Strong intent, P1 coordinate fix.

WORLD 1 (free, L1-L10 — the conversion engine): The hook works in CONCEPT (rip the status bar, blow on the mic, screenshot-to-freeze, flip dark mode) but is undercut by execution: L1 fallback softlock + jumpable pit (mechanic bypassed on the teaching level), L2 1-second retraction death-loop, L3 inverse-laser hint teaches the lethal behavior, L5 is unwinnable (static-body physics impossibility) and a passive cutscene, L9 crusher kills you mid-read, L10 (last free level) tree never grows on device + no fallback. L8 (dark mode) is the standout at 4/5. This slice MUST hook to convert and currently has multiple free-slice frustration spikes and two unbeatable levels.

WORLD 2 (paid, L11-L20 — first impression of the IAP): The weakest paid world and the worst place for it. L11 is a one-tap no-puzzle that softlocks if you follow its own instructions; L12 clipboard clobber + jumpable door; L14 is unwinnable (inverted exit gate, DND never detected, toggle self-reverts); L15 mechanic bypassable + event clobber kills you mid-jump; L16 shake-undo never required + broken moving platform; L17 self-defeating animation + iPad softlock; L18 solution renders off-screen + dead primary path; L19 FaceID softlocks on iPad; L20 boss is a non-interactive cutscene. A paying customer's FIRST paid level (L11) is an 'is that it?' moment.

WORLD 3 (paid, L21-L25): Better concepts (talk to your phone, low-battery reveals the real exit) but thin execution: L21 mechanically thin + broken iPad layout; L22 mechanic is a dev-labeled 'SIM DRAIN' button; L23 is a scripted cutscene whose name-hook breaks on iOS 16+ ('HELLO, IPHONE'); L24 flat-floor + one button; L25 iPad softlock + unfair day mode + unreachable secret hour. Charming writing carrying weak mechanics.

WORLD 4 (paid, L26-L30 'Reality Break'): The boldest ideas (change your phone's language, VoiceOver-to-see) but the most fragile. L26 iPad softlock + no fallback + false auto-solve for non-English devices; L27 is self-defeating (enabling VoiceOver disables the touch controls the level needs); L28 is a ceremonial non-puzzle, unbeatable on iPad; L29 (The Lie) is one of the cleverest beats in the game but its reveal renders off-screen; L30 fires the game-ending credits 4 levels early then loads L31.

WORLD 5 (paid, L31-L33 — the climax): The steepest difficulty wall right before the finale, with the two worst fallback gaps. L31 (Flashlight) torch can't be detected + no fallback = dark-cave softlock; L32 (Multi-touch) renders its solution off-screen on every device + impossible ergonomics + dead fallback; L33 (App Review) is a clever satire undermined by a double auto-review prompt (compliance risk) and a passive cutscene. The campaign currently cannot be finished here.

## Fix Roadmap

Sequence by ship-blocking impact, then payability, then polish.

PHASE 0 — Submission unblockers (must precede ANY paid launch; ~1 week):
1. Decide the device story NOW: set the app target's TARGETED_DEVICE_FAMILY to '1' (clean iPhone-only) and delete the misleading dead iPad code — this single decision removes ~28 iPad softlock blockers at once. Do NOT ship universal until Phase 2's geometry pass is done.
2. Add the persistent in-level pause/back button (HUDLayer -> togglePause) — the single highest-leverage fix; it converts every device-puzzle softlock from a hard dead-end into a recoverable exit.
3. Compliance: remove the L33 auto-review prompt; either finish or cut the devcommentary IAP; add price + purchase/restore result alerts to the paywall.

PHASE 1 — Make the paid slice actually completable (~1-2 weeks):
4. Fix the unwinnable paid levels: L5 (kinematic carry), L14 (invert exit gate + stop the self-revert), L32 (camera-coord fix + ergonomics), L31 (real torch + fallback), L18 (deliver an actual solve path). Fix the free-slice L10 clobber + fallback (last free level must be beatable to convert).
5. Add hardware fallbacks to L19/L26/L7; wire the simulator forceHardwareFallback so App Review can complete every level.

PHASE 2 — Make it worth paying for (~2-3 weeks):
6. Rebuild the hollow mechanics (L11/L13/L16/L17/L20/L23/L24/L25/L29) so the device feature is genuinely required, not auto-solved/bypassable.
7. Wire Game Center (achievements/leaderboards + UI) for the retention layer, or cut the entitlement.
8. Free-slice polish that drives conversion: L1 fallback+pit, L2 retraction, L3 inverse-hint, L9 crusher grace — these four are the conversion funnel.

PHASE 3 — Premium finish (~1-2 weeks):
9. Camera-anchor all full-screen juice (fixes off-screen L0/L29 payoffs); enable scanlines; swap Helvetica->Menlo titles; raise per-world atmosphere; recolor confetti.
10. Move audio synthesis off-main + cap particles; honor system Reduce Motion/Dynamic Type; wire or remove the dead accessibility toggles; resolve narrator identity + reorder the L30 credits.

If forced to ship sooner: do Phase 0 + Phase 1 (steps 1-5) and release iPhone-only with paid levels gated; that at least removes the rejection risk and the unbeatable-level refunds, even if the 'tech demo' feel remains.

## Per-Level Ship Scores

| Lvl | World | Mechanic | Ship (1-5) | Verdict |
|---|---|---|---|---|
| 0 | 0 | Boot/intro sequence | 3 | Charming, on-brand cold open with a smart fake-crash hook, but the signature payoff and an entire victory layer render off-screen due to a camera-at-origin vs effects-at-size/2 mismatch, and the unskippable ~12s scripted intro plus a touch-only required drag (no keyboard/reduce-motion fallback) keep it short of the premium bar — fix the coordinate bug and add skip/fallbacks and it's ship-quality. |
| 1 | 1 | Status bar / notch header | 2 | A genuinely clever fourth-wall opener undercut by a fatal iPad/sim fallback softlock, a phone pit that lets players skip the whole mechanic, and a stretched-phone iPad layout — fix the P0 fallback and the pit width before this teaches or sells anything. |
| 2 | 1 | Microphone (blow) | 3 | A beautifully drawn, well-scaled level with a charming hook that's undermined by a self-contradicting bridge that retracts in ~1 second and de-solidifies under the player — fix the retraction/grounded bug and it jumps from a death-loopy tech demo to a 4/5 free-slice charmer. |
| 3 | 1 | Screen static / signal | 2 | Clever inverse-shield concept undone by an undiscoverable reversed-laser twist and a single-pulse fallback that's unbeatable on simulator/hardware-free mode — fix the fallback, force-simulator-fallback, and telegraph laser #4 before this free-slice level can convert anyone. |
| 4 | 1 | Volume buttons | 2 | A charming wolf-and-water premise that mechanically collapses to "hold your volume low and walk right" — the detection zone covers the whole level so there's no sneaking, and the advertised flood hazard is unreachable because the wolf always kills first; needs a real spatial puzzle and a threshold redesign before it earns its spot in the free conversion slice. |
| 5 | 1 | Charging / plug in | 1 | Beautiful idea, broken execution: the 'ride the plug' verb is built on a SpriteKit impossibility (static bodies don't carry the player) and the plug sweeps up through the player from below, so the level cannot be completed via its own mechanic — and even fixed, it's a passive cutscene, not a level. Do not ship. |
| 6 | 1 | Screen brightness | 2 | A clear, charming, well-juiced brightness puzzle on iPhone that is hard-softlocked and unbeatable on every iPad in the matrix — fix the iPad stagger before this can ship. |
| 7 | 1 | Screenshot (freeze) | 2 | A clever, genuinely funny screenshot-to-freeze mechanic with thoughtful telegraphing — but it ships as a hard softlock on Simulator and for any non-screenshotting player because, unlike its sibling levels, it never wires up an automatic fallback, making it an App Review rejection waiting to happen. |
| 8 | 1 | Dark/Light mode toggle | 4 | Mechanically sound, completable across the full device matrix, and genuinely fun — ships at 4/5 once the iPad HUD anchoring and the t=0 panel overlap get the same centering love the course already received. |
| 9 | 1 | Device rotation | 2 | A genuinely clever, completable rotate-the-world capstone undercut by a 2.5s no-grace crusher and an 18s-late hint that punish the player mid-discovery — fix the pacing/clue timing (P0) and the landscape text distortion (P1) and this becomes a 4-5; as-is it's a refund-risk frustration spike on a level that's supposed to sell the game. |
| 10 | 1 | Background app / time passage | 2 | Charming finale concept undone by a real-device softlock: the background-time event is clobbered before it can grow the tree, and there is no production fallback — unbeatable as shipped for most players on the last free level. |
| 11 | 2 | Notifications | 2 | A no-stakes one-tap "puzzle" that teaches a play pattern which softlocks it, is uncompletable on iPad, and whose only charm is hidden behind failure — not ship-ready as the gateway to the paid tier. |
| 12 | 2 | Clipboard / paste | 2 | A clever clipboard premise undermined by a state-clobber bug that breaks its own copy-then-return instructions, a door you can just jump over, no accessibility fallback, and geometry that becomes an uncrossable void on iPad — not shippable as a paid level until completability is fixed. |
| 13 | 2 | WiFi toggle | 2 | Clever mechanic and a completable core path, but a one-directional accessibility fallback with no respawn-reset creates a permanent softlock, and the marquee download objective is cosmetic — not shippable until both are fixed. |
| 14 | 2 | Focus / Do Not Disturb | 1 | Strong concept, broken execution: the exit is barred exactly when the level is safe, the DND detector doesn't detect DND, the manual toggle self-reverts in half a second, and the layout softlocks on iPad — this is currently unwinnable and not shippable. |
| 15 | 2 | Low Power Mode | 2 | Great premise, broken puzzle: the Low Power mechanic is bypassable in normal gravity, a real device event can flip gravity mid-jump and kill the player, and the fixed-390pt layout collapses on iPad — three P0s keep this paid-slice level well below ship quality despite genuinely premium juice. |
| 16 | 2 | Shake to undo | 2 | A clever, charming premise undercut by execution: the shake-undo mechanic is never required (pure decoration), the one interactive platform uses broken static-body motion, the undo teleport fights physics and can kill you, there's no accessibility fallback, and iPad shows a phone-sized strip in a sea of empty space — not yet shippable for a paid world. |
| 17 | 2 | Airplane mode | 2 | A brilliant on-theme gag wrecked by an iPad softlock, a self-defeating animation bug, and a real-device mechanic with a one-way fallback — needs real work before it earns its IAP slot. |
| 18 | 2 | App switcher | 1 | Clever idea, broken execution: hard-softlocks on iPad, the advertised primary solve event is never delivered, the freeze fires backwards relative to the gesture, and there's no fallback — not shippable without a substantial rework. |
| 19 | 2 | Face ID | 2 | Killer 15-second Face ID gimmick, but it is unbeatable in hardware-free mode and on iPad (no fallback, proximity-only), accuses players of being imposters for tapping Cancel, and has no platforming between scans — strong concept, not yet a shippable paid level. |
| 20 | 2 | World 2 boss / meta | 2 | Beautifully juiced but mechanically hollow: a one-direction walk into an auto-triggering cutscene wall — a tech-demo finale that needs a real player-driven choice and a replay skip before it earns its spot in the paid tier. |
| 21 | 3 | Voice / speech recognition | 3 | A charming 'talk to your phone' concept that's mechanically thin and shipping with a broken iPad vertical layout, a hardware-free fallback that can only say 'open', and a 6s timer that spoils the voice magic — fixable, but not ship-quality for a paid World-3 level as-is. |
| 22 | 3 | Battery percentage | 2 | A clever low-power puzzle idea undermined by a debug-button mechanic, an iPad layout that strands gameplay in the bottom 15% of the screen, and a de-solidify grounded bug — not ship-ready for a paid World-3 slot without the P0 fixes. |
| 23 | 3 | Device name | 2 | A scripted cutscene masquerading as a puzzle: the name-based "prove you're real / beat the doppelganger" mechanic is entirely fake (timers, not gameplay) and the personalization hook breaks on iOS 16+ — not ship-quality for a paid level. |
| 24 | 3 | Storage space | 2 | Mechanically completable and charming in writing, but it is a flat-floor-plus-one-button tech demo whose actual device mechanic is undiscoverable and bypassed by its own fallback — not a level a paying World-3 customer would feel was worth the IAP. |
| 25 | 3 | Time of day / clock | 2 | Brilliant device hook undercut by an iPad softlock, an unfair/near-impassable day mode, and a near-unreachable secret hour — completable on iPhone via the toggle but currently a 1-star-on-iPad, "tech demo" experience that needs a layout and difficulty pass before it justifies the paid slice. |
| 26 | 4 | Language / locale | 2 | A brilliant one-time fourth-wall stunt undermined by an iPad-breaking hardcoded layout, no non-hardware fallback (softlock), and a false auto-solve for the world's non-English players — fix the P0s before this paid-tier level ships. |
| 27 | 4 | VoiceOver | 1 | Conceptually beautiful but mechanically self-defeating: enabling real VoiceOver kills touch controls, the iPhone geometry collapses the "gap" into a solid blind-walkable slab, and there is no toggle-free fallback — a near-certain softlock/refund on device. |
| 28 | 4 | Share code / AirDrop | 2 | A ceremonial non-puzzle that is unbeatable on iPad and has a dead accessibility fallback — two P0 completability blockers plus a hollow mechanic make this a refund risk for the paid World 4 slice; not shippable until geometry, fallback, and the core puzzle are reworked. |
| 29 | 4 | Meta / narrative twist | 3 | Brilliant meta premise, but the reveal's signature glitch/flash renders off-screen (camera is far-right, effects are scene-centered) and the ~13s no-skip cutscene drags — fix the camera-relative effects before shipping. |
| 30 | 4 | Credits finale | 2 | A brilliant fourth-wall finale concept undermined by a game-ending sequence that fires mid-campaign and then loads the next level, plus stacked victory juice and bugs camped on forced landing spots — completable, but feels broken at the exact moment it must feel triumphant. |
| 31 | 5 | Flashlight / torch | 1 | A beautiful dark-cave lighting shader wrapped around a non-functional mechanic: the torch can't be detected as designed, the ceiling hazards literally can't hit you, there's no auto-fallback, and the start screen has no visible instructions — a P0 softlock and an unshippable World-5 paid level until the core loop is rebuilt. |
| 32 | 5 | Multi-touch | 1 | Hard-softlocked and unshippable: a scene-coords-in-camera-space bug renders all Section-3 plates off-screen on every device (level uncompletable), the advertised hold-while-moving mechanic is fake (gates latch on a momentary tap), the 4+1-finger ergonomics are physically impossible on phones, and the accessibility fallback is non-functional — a charming idea that was clearly never run on a device. |
| 33 | 5 | App review / meta finale | 3 | A charming-but-passive cutscene-as-level whose headline device mechanic (a real review prompt) silently no-ops for most players and whose finale is undercut by an auto-fired choice and a colliding generic victory effect — completable and bug-light, but not yet ship-quality for a paid finale. |

## Dimension Readiness

| Dimension | Readiness (1-5) |
|---|---|
| difficulty-curve | 3 |
| accessibility | 2 |
| visual-juice | 3 |
| device-ipad | 3 |
| monetization-value | 2 |
| stability-perf | 4 |
| appstore-compliance | 2 |
| onboarding-flow | 2 |
| narrative-voice | 3 |
