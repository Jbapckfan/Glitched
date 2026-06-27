# Glitched — Round-2 Consensus Triage (code-grounded)

Each level's 4–5 blind round-1 reviews reconciled by a fresh adjudicator that read the **current** (post-PR#15) source and tagged every finding `real-unfixed` / `already-fixed` / `false-positive` / `new`.

**Coverage: 28/34 levels.** Missing (re-run pending): [16, 17, 18, 19, 20, 23].

- **Survivors to act on (real-unfixed + new): 92**
- Thrown out — false-positives: 140 · already-fixed (PR#15 etc.): 30
- Contested (want a Gemini/DeepSeek tiebreak): 0

## Fix backlog — survivors by severity


### 🔴 CRASH / SOFTLOCK

- **L5 ChargingScene — iPad softlock when device is already charging at level launch** 🆕
  - `Level5_Charging.swift:160-164 (auto-trigger) + setupBit:709-713 (iPad spawn) + triggerPlugAnimation:859 (gated by !hasPlugArrived)` · raised by: adjudicator
  - On iPad the spawn is relocated OFF the central boarding platform to the bottom-left climb base (x=130). But if UIDevice is already charging/full at configureScene, the plug auto-triggers at t=0.8s and rides the elevator to the top EMPTY (Bit is on the left climb, plugContactCount==0). After arrival, triggerPlugAnimation is hard-gated by hasPlugArrived, so replug can't summon it again. The iPad climb deliberately cannot reach the exit on its own (bridge >maxRise below exit, peak >maxGap away) — it only deposits Bit on the boarding platform. With the plug parked unreachably at the top, a player who climbs without dying is stranded forever. (Dying accidentally rescues them, since post-arrival spawnPoint is moved onto the exit platform — but that requires a death.) iPhone is immune because it spawns ON the boarding platform and rides the plug up. FIX: on the isWideCanvas path, defer the already-charging auto-trigger until Bit reaches/contacts the central start platform, or relocate the iPad spawn onto the boarding platform, or let .deviceCharging re-arm the plug when Bit is at the boarding point and hasn't yet ridden.
- **L11 NotificationScene — Granted permission + banner dismissed without tapping = softlock (no in-app recovery)** 🆕
  - `Level11_Notification.swift:994 handleGameInput / requestNotification:749` · raised by: adjudicator
  - When notifications are GRANTED, the only unlock path is physically tapping the OS banner (NotificationDelegate.didReceive → InputEventBus.notificationTapped → unlockCurrentDoor). The scene handles only .notificationTapped and ignores .notificationReceived (fired on schedule, line 125 of NotificationManager), so no in-app tappable target is created. The in-app faux notification is created ONLY on permission-DENIED. If the player swipes/dismisses the foreground banner without tapping (very common), pendingNotificationId stays non-nil so requestNotification's `guard pendingNotificationId == nil` blocks re-requesting, AND the manager's pendingNotifications[id] is never cleared (only handleNotificationTapped/deactivate clear it) so observeForegroundForRearm's `!hasPendingNotification` re-arm never fires even after backgrounding. The give-up auto-unlock is unreachable because it needs a 3rd request the guard blocks. Net: that door is permanently soft-stuck. FIX: handle .notificationReceived(id:) for the genuine pending id by showing the same tappable in-app faux notification used on the denied path (always recoverable in-app), or clear the re-request guard once the notification has fired.

### 🟠 FAIRNESS

- **L1 HeaderScene — Missed manual drop consumes the banner permanently (no re-show, non-obvious recovery)** 🆕
  - `LevelHeaderHUD.swift:142-151 (hasDropped=true) + GameRootView.swift:44 (HUDLayer keyed on levelID)` · raised by: adjudicator
  - The HUD sets hasDropped=true (banner vanishes) for ANY drop past size.height/3, BEFORE the scene decides accept/reject. A drop that passes the HUD gate but fails the scene gate (e.g. dragged down-and-left to x<~36 on iPhone) calls notePlayerStruggle() with NO bridge AND the banner gone. hasDropped is @State on LevelHeaderHUD whose identity is keyed on levelID, so a reboot/respawn in the SAME level does NOT reset it — the banner never returns. Recovery exists only via the always-present cyan fallback button, which a player has no reason to know is now their sole path. Recommendation: only set hasDropped after the scene confirms a bridge (gate the consume on bridgeSpawned), OR snap the banner back on a scene-rejected drop.
- **L3 StaticScene — TEACH laser hit-zone overlaps the spawn platform's near edge by ~5pt on the wide-spawn / narrow-next pairing** 🆕
  - `Level3_Static.swift:599-605 (composedLaserSpecs lx = midpoint of platform CENTERS), 552-553 (switchback x)` · raised by: adjudicator
  - The laser x is the midpoint of the two platform CENTERS, not the geometric center of the GAP. When a wide platform (176) sits opposite a narrow one (76), the wider deck's near edge reaches exactly columnGap/2 (25pt) from center — the same x as the laser — so the hit-zone (half-width 5*visualScale, base = deck-20) overlaps the wide deck edge by ~5pt. I reconstructed the full iPad seq and only gap(0,1) (the TEACH laser bracketing the wide tier-0 spawn) hits lx==aNear. A player standing at the spawn's jump-off edge in dead silence could graze it. MITIGATED: the player is explicitly taught to make noise, which turns this exact laser OFF before crossing, so it is an edge-clip not a guaranteed death. Fix: anchor lx to the gap geometric center ((aNear+bNear)/2) instead of (xs[a]+xs[b])/2, or hold the hit-zone a few pt off the lower deck. 1-line change.
- **L6 BrightnessScene — Sun/burn hazard active on load if device starts at/above 0.95 brightness, before any teach beat** 
  - `Level6_Brightness.swift:101-106 (configureScene seeds currentBrightness then updateBurnZones/updateMaxBrightnessSun) + :531-555 (sun hazard enable) + :344-376 (burn zones enable)` · raised by: codex,kimi
  - Real but mitigated. Entering at >=0.95 immediately enables the sun hazard body and burn-zone hazards. However the spawn is at the bottom of the climb and ALL hazards are clustered at the TOP (burn zones over the top platforms; sun over the finale summit), so there is no spawn-kill or first-jump death — the player must climb several platforms before reaching the kill band, and updateBrightnessCommentary() at l106 fires the 'MY EYES! THE GOGGLES DO NOTHING!' alert on load as a verbal warning. So a teach signal exists even when entering hot. Codex/kimi flagged correctly. Optional fix: keep hazard bitmasks disabled until at least one UV platform has solidified once (or until the player has lowered then re-raised brightness), giving a clean first solidify before the ceiling can kill.
- **L9 TimeTravelScene — Backgrounding to upgrade the tree while standing on a lower branch drops Bit (foothold removed mid-stand)** 🆕
  - `Level10_TimeTravel.swift:1179-1201 growTreeToStage` · raised by: adjudicator
  - growTreeToStage removes the old fullTreeNode (current branch) and rebuilds the next tier collision-DISABLED for a 1.5s grow, after a 1.5s SYNCING overlay. If the player climbed the young/mature ladder then backgrounds again to advance, the foothold vanishes and Bit falls to the death zone and respawns at spawnPoint. Not a softlock (respawn lands on the launch floor and the now-grown tree is fully climbable) and uncommon, but it silently erases climb progress. Low priority; if touched, snap Bit to spawnPoint or briefly suspend the death zone during a re-grow.
- **L11 NotificationScene — iPad decoy fires 1s before genuine; intro never names the GLITCHED sender (first-encounter fairness)** 
  - `Level11_Notification.swift:783 (decoy delay) / 680-699 instruction panel` · raised by: codex,kimi,gemini
  - Decoy 'SYSTEM' alert is scheduled at max(0.5, realDelay-1.0)=2.0s, genuine 'GLITCHED' at 3.0s, so the first banner a first-timer sees is the decoy, and the instruction panel ('WAIT FOR THE ALERT') never tells them to tap the GLITCHED sender vs avoid SYSTEM. Mitigated: tapping the decoy is fully recoverable (handleDecoyTapped re-arms + narrator 'THAT WASN'T ME. TAP THE BELL AGAIN.'), and the give-up auto-unlock skips the decoy. Real but mild — a one-time speed-bump, not a softlock. FIX: brand the genuine sender in the intro ('look for GLITCHED, ignore SYSTEM') or delay the decoy until after the first successful unlock.
- **L21 DeviceNameScene — iPhone bay3 reachability proof is numerically wrong; Bit squeezes against pillar2 but still contacts door3 exit** 🆕
  - `Level23_DeviceName.swift:908-916 (setupBit clamp) + installBayPillars:553-564` · raised by: adjudicator,kimi
  - The clamp comment claims maxX = courseX(430)-11 = 379, using HALF the real body width. PlayerController uses halfWidth = character.size.width/2 = 22 (body is 44 wide) and boundaryPadding 20, so real maxX on a 390pt iPhone is 368, not 379 (375->353, 393->371). At that clamp Bit's 22pt physics body [357,379] straddles solid pillar2 [351,360] AND overlaps the 30pt-wide door3 exit body [358.7,388.7] from 358.7..379 — so door3 (the rightmost real door, reachable via hash%3) STILL completes on every iPhone width, but only because the exit body is wide; Bit visibly jams against pillar2 at the clamp. Kimi's 'physics squeeze' was directionally right (though wrong that it's a softlock or that bays are < the 44pt body — the body is 22pt). Recommendation: fix the comment's math and either nudge worldWidth ~+12 or shift the rightmost slot/pillar left a few pt so Bit seats cleanly in bay3 instead of relying on exit-body overlap while pinned to a pillar.
- **L22 VoiceCommandScene — FLY gate keys off transient bridgeExtended, which auto-retracts after 5s — a legitimately-crossed player gets the wrong 'SPEAK BRIDGE AND OPEN FIRST' rejection** 🆕
  - `activateFly() line 803; retract at extendBridge() lines 753-758` · raised by: adjudicator
  - guard bridgeExtended && doorOpened uses the LIVE bridge flag, which flips back to false 5s after BRIDGE is spoken (auto-retract). A deliberate player who says BRIDGE, walks the ~227pt span, then reaches the FLY point past the cleared door more than 5s later finds bridgeExtended==false, so FLY is rejected with a misleading 'SPEAK BRIDGE AND OPEN FIRST' even though they already crossed. Recoverable (re-say BRIDGE from the far side to re-set the flag, or the base no-progress fallback shows hintText within ~22s), so fairness not softlock — but it is a real first-encounter trap none of the 5 reviewers caught precisely. Fix: gate FLY on a LATCHED 'bridge has been extended at least once' flag (parallel to flyUsed), not the transient bridgeExtended.
- **L22 VoiceCommandScene — iPhone locked door keeps 90pt height (top ~+105) vs iPad 107pt — ~1pt over-clearance allows a frame-perfect skip on iPhone only** 
  - `buildPhoneLevel() line 233 (door at groundY+60, default height 90); iPad line 386 uses 107` · raised by: deepseek,kimi
  - Real and asymmetric. Door center groundY+60, height 90 -> top groundY+105. Bit body bottom at apex ~groundY+106 (apex ~91 above the platform-top stance at groundY+15), i.e. ~1pt above the door — a max-height frame-perfect jump can clear OPEN's door on iPhone. The iPad path deliberately raised the blocker to 107pt for exactly this margin (per the line 386 comment), so the iPhone path was left with the unsafe margin. Low player impact (requires near-perfect input and only skips one of three gates) but it is the gating mechanic. Fix: pass height:107 on the iPhone door too.
- **L25 TimeOfDayScene — Enemy teleports to patrol origin on switch back to DAY, can hit player unfairly** 
  - `Level25_TimeOfDay.swift:691-701 (applyDayMode snap to patrol.origin)` · raised by: gemini
  - Real but narrow. On a NIGHT/secret->DAY transition a sleeping spike is removeAction'd, hard-snapped to patrol.origin, and re-armed to .hazard in the same frame. Because the guard's origin sits on P2's landing (where the player stands after crossing in NIGHT), if the player cycles all the way back to DAY while standing there, the spike can materialize on top of Bit = an instant death with no visible approach. Low practical reach (requires the player to tap night->secret->day after already crossing, and they have no reason to). The snap is deliberate (avoids patrol center drift per the comment), so don't remove it — but ease/move the spike back over ~0.15s, or re-arm the hazard mask only after it has eased home, to remove the teleport-onto-player frame. Polish-to-fairness; lowest priority of the survivors.
- **L25 TimeOfDayScene — Guard spikes sit on the left shoulder of P2, not centered over the only landing — puzzle may read as a timing/position dodge** 
  - `Level25_TimeOfDay.swift:359-363 (phone enemyData: guard center 250, range 35 -> sweep [215,285]) vs P2 span [220,310]` · raised by: claude
  - Phone-only first-encounter clarity. The guard's awake DAY sweep covers [215,285] while P2's full top is [220,310], so the right ~25pt of P2 ([285,310]) is never swept — a first-timer can read 'just land far right of the spikes' and beat the forced jump without ever switching to NIGHT, weakening the required-mechanic read. The level is still completable and the intended solution still works; this is a teach-clarity gap, not a softlock. Fix: widen the guard (range ~45) or shift its center right so the awake DAY sweep makes EVERY viable P2 landing lethal, converting it from a dodgeable beat into an unambiguous must-sleep gate. The composed-iPad guard (range 70 over the full pad span) already does this correctly; only the phone path is loose. Highest player-impact survivor.
- **L26 LocaleScene — Solving while standing on a wrong platform de-solidifies footing under Bit, dropping him to the death plane** 🆕
  - `Level26_Locale.swift:719-725 (unscrambleWorld wrong-platform fadeout) / 222,428 (death zones)` · raised by: adjudicator
  - NEW edge: in unscrambleWorld() wrong platforms fade 0.3s then set categoryBitMask=.none. If the player changes language while standing ON a climbed wrong pad (e.g. iPhone w1 at g+80, or iPad w2/w3), there is no hidden pad directly beneath (hidden pads sit ABOVE), so Bit falls to the hazard plane. Mitigations that cap severity: (a) 0.3s fade gives a brief window, (b) handleDeath RESPAWNS at spawn — no softlock, no lost progress, and puzzleLatched keeps the route solved so the retry is trivial, (c) most players solve from spawn/rest, not mid-wrong-climb. Low-impact; optional fix is to delay wrong-platform de-solidify until Bit is not resting on it (groundNode check) — not worth blocking ship.

### 🟡 POLISH

- **L0 BootSequenceScene — Inherited 18s no-progress hint panel shows off-theme generic copy** 🆕
  - `Level0_BootSequence.swift (no hintText() override) → BaseLevelScene.swift:704/:784 hintText() ?? "Try using your device's features..."` · raised by: adjudicator
  - The scene is .playing from didMove (inherits base runIntroSequence→startPlay), so the base update() no-progress nets fire here. A player still stalled at ~18s gets the base difficulty panel reading 'Try using your device's features...', which is nonsensical for a drag-the-loading-bar boot screen. The 6s idle-nudge already gave correct guidance, so impact is low, but the copy mismatch is real and was missed because reviewers saw an older build. Fix: override hintText() to return e.g. 'Drag the white dot all the way right to boot.' Polish-tier.
- **L1 HeaderScene — iPhone t=0 whisper low-contrast (accent on white) and competes with spawning Bit** 
  - `GlitchedNarrator.swift:101,227 (.whisper uses Colors.accent, no backing plate) + Level1_Header.swift:109-112` · raised by: claude,codex
  - Grounded: .whisper renders Colors.accent glyphs with only RGB-split ghosts and NO solid backing plate, so on L1's white foreground background it can read low-contrast and sits in the lower-center band near spawn. But this lives in shared GlitchedNarrator and affects every whisper, so it's a cross-cutting polish item, not L1-specific. Recommendation: add a faint dark backing plate to the whisper style (helps all levels).
- **L4 VolumeScene — hintText() is a full reveal / no graduated 'too loud' vs 'water rising' ladder** 
  - `Level4_Volume.swift:1607` · raised by: deepseek,kimi,claude
  - Genuinely present: hintText() returns one static string naming Volume-Down outright, and notePlayerStruggle() only escalates that single string. The atmospheric t=0 panel + wolf sleep-talk provide softer cues first, and the hint only fires after struggle/idle, so it isn't an immediate spoil. A context-sensitive ladder (vague quiet cue → water cue → explicit button) would be nicer but is pure polish, not fairness — the player has earned the reveal by the time it shows. Optional: keep current single hint; low priority.
- **L5 ChargingScene — didEnd unconditionally schedules setGrounded(false) even if another ground body still touches** 
  - `Level5_Charging.swift:1137-1151` · raised by: deepseek
  - didEnd clears grounded after 0.05s with no 'still-touching' guard, so stepping off one platform while resting on another briefly marks Bit airborne. In L5 the practical impact is negligible: climb platforms are spaced so Bit isn't straddling two ground bodies, the 0.16s coyote window (PlayerController:26) covers the 0.05s false-airborne gap for jumping, and the plug->exit dismount ends the level on contact. Shared base-pattern nit; fix by only clearing grounded when no ground contact remains, but low priority for L5.
- **L6 BrightnessScene — Instruction panel never auto-dismisses if device enters above 0.6 brightness** 
  - `Level6_Brightness.swift:1668-1679 (dismiss guard) + :101 (initial read) + BrightnessManager.swift:24-26 (activate re-posts current brightness)` · raised by: kimi
  - Confirmed real. configureScene sets currentBrightness = UIScreen.main.brightness (l101), then BrightnessManager.activate() async-posts brightnessChanged(currentDeviceBrightness). In handleGameInput the dismiss/notePlayerProgress fires only when `level > 0.6 && oldBrightness <= 0.6`; if the device starts >0.6 then oldBrightness is already >0.6 so the guard is always false — the BRIGHTNESS tooltip persists forever and notePlayerProgress is never called. Not a softlock (platforms are already solid, level fully completable; the base wall-clock hint fallback still works). Kimi was right. Fix: on load, if the initial brightness already clears the ghost threshold, fade the panel and call notePlayerProgress().
- **L7 ScreenshotScene — iPad: finale chasm/exit scroll off-screen at spawn; upper-center canvas reads dead-white** 
  - `Level7_Screenshot.swift:456 buildComposedIPadLevel; setupBit:955 installCameraFollow` · raised by: claude
  - True but minor: this is a horizontally-scrolling course (camera-follow clamps to courseExtent, exit IS reachable on-screen as the player climbs) — analogous to any side-scroller where the goal isn't visible at spawn. The exit arrow + staircase guide direction. Optional polish: seed a faint ghost-preview of the finale bridge or a directional cue so the mid-canvas isn't empty at t=0. Not a fairness/completability issue.
- **L7 ScreenshotScene — Hints don't escalate gradually — single full-answer reveal rather than soft-nudge-then-reveal** 
  - `Level7_Screenshot.swift:1216-1227 handleDeath (only notePlayerStruggle); 1251 hintText` · raised by: gemini,kimi
  - Accurate as a polish note: handleDeath only calls notePlayerStruggle() and the reveal is one-shot (full button combo at 2 deaths / 8s). gemini/kimi's "waits 18s" is overstated — the struggle path fires at the 8s floor after 2 deaths, not 18s. Optional nicety: override to show a soft "a screenshot pins a moment" after death 1 and the explicit combo only after death 3. Low impact; current behavior is already fair.
- **L8 DarkModeScene — iPad climb pins every beat near the combined jump ceiling (85pt gap + ~82pt rise simultaneously)** 
  - `Level8_DarkMode.swift:630 pitch=200 / :620 tierStep` · raised by: codex,adjudicator
  - Verified numerically: iPad gap is exactly 85pt edge-to-edge (pitch 200 − halfW 65 − halfW 50) and tierStep is ~78–83pt on every beat. Each is individually within budget (gap«130, rise<85 safe), and the jump IS completable — Bit arrives over platform B's top at y≈88 (>82 surface) while descending, ~6pt vertical clearance. But it is a near-max DIAGONAL on literally every beat with no breathing room except the one rest pair, so it feels relentless and unforgiving on iPad. Codex was directionally right; his 'exact ceiling' wording overstated (tierStep is under 85, gap is well under 130). Recommend widening solid/dual platforms by ~15–20pt or dropping pitch to ~185 to buy margin on the diagonals. Not a softlock.
- **L8 DarkModeScene — iPhone rest->door bypass-block depends on step hitting its 50pt cap** 🆕
  - `Level8_DarkMode.swift:439 step=min(50,riseBand*0.10) / :526 doorPlatformY` · raised by: adjudicator
  - The 3.55 multiplier closes the rest->door skip (107.5pt > 91 apex) ONLY when step==50, which needs riseBand>=500. Verified every real portrait iPhone (SE 667 → riseBand 527, up through Pro Max) clamps step to 50, so the bypass stays blocked TODAY, and the app is portrait-locked (Info.plist single UIInterfaceOrientationPortrait). But the guard is implicit: if a future smaller canvas / split-view / orientation drop ever pushes riseBand below ~500, step shrinks and rest->door silently falls under the apex (86.5pt at step=40), re-opening the very dark->light flip-skip this commit was meant to prevent. Recommend computing the door multiplier from a fixed apex margin rather than assuming step==50, or asserting step==50 on phone. Latent only — not reachable on shipping devices.
- **L10 OrientationScene — iPad portrait wastes canvas — flat course marooned lower-left, upper/right read as empty grid; iPhone clips crusher/skull off left edge** 
  - `Level9_Orientation.swift:137-198 cacheIPadFramingIfNeeded lift; 367-491 drawIPadRightShaft; 300-302 phone worldNode pin` · raised by: claude
  - Genuine but cosmetic. The current code already added a substantial lift (walk line targeted ~0.44 of band) plus drawIPadHazardFraming/drawIPadRightShaft to dress the exposed bands, so it is much improved from the reviewed build, but the framing is still a centered/lower-weighted strip rather than truly edge-to-edge, and on iPhone the crusher (the motivator to flee right) starts partly off the left edge by design (crusher local x=70, left edge of 150-wide body at -5 screen-ish under fit scale). Lowest-priority visual polish; mechanic and reachability are unaffected. Optional.
- **L11 NotificationScene — iPad door geometry overlaps adjacent platforms (door 0 into spawn pad/rung-1; door 1 into top landing)** 
  - `Level11_Notification.swift:394 (door0) / 430 (door1)` · raised by: claude,kimi
  - Verified by geometry sim. Door 0 (center rungX(0)+100=230, w45) overlaps the 200-wide tier-0 pad's right edge by ~22.5pt and the tier-1 rung's left edge by ~27.5pt — the 'tangled spawn intersection' Claude flagged (note: the older 'L-shaped block' is gone in current code). Door 1 (center rungX(top)-70, w45) overlaps the 170-wide top-tier landing's left half by ~37.5pt, and on odd topTier its left edge also overlaps the previous rung by ~7.5pt. Both doors' 115pt ground-blockers sit embedded in solid platforms while LOCKED. Functionally the gate still works (blockers removed on unlock; reach budgets all within 85/130 — confirmed) and post-unlock the landing/exit are clean, so it is a visual-seam + potential mid-jump snag, not a softlock. iPad-only. FIX: nudge each door into the inter-platform gap so door art reads as distinct from the platforms.
- **L11 NotificationScene — Static hintText never names the GLITCHED-vs-SYSTEM choice or the dropped rung** 
  - `Level11_Notification.swift:1113 hintText()` · raised by: codex,kimi
  - Partial-correction of the reviewers: the hint system IS wired and DOES escalate — notePlayerStruggle (called on every death, line 1095) increments struggleCount and after >=2 struggles + >=8s triggers showDifficultyHintIfNeeded → hintText reveal (BaseLevelScene:744-768). What is true: the text is a single static sentence ('Wait for the notification, then tap it to unlock the door') that never adapts to the actual failure mode — a player repeatedly tapping the decoy or missing the signal-dropped rung gets the same unhelpful line. FIX (polish): branch hintText on a decoy-tap counter ('LOOK FOR THE GLITCHED SENDER, NOT SYSTEM').
- **L12 ClipboardScene — Background clipboard poll auto-solves the puzzle and contradicts the level's 'string read is user-initiated only' claim** 
  - `ClipboardManager.checkClipboard():46-62 + Level12 handleGameInput:652-661` · raised by: codex,adjudicator
  - On a real device usesHardware(.clipboard) is true, so DeviceManagerCoordinator.configure activates ClipboardManager's 0.5s polling timer, which reads UIPasteboard.general.string (guarded only by changeCount/hasStrings) and posts .clipboardUpdated -> handleGameInput -> checkPassword. So when the player returns with GLITCH3D copied, the level auto-unlocks BEFORE they tap PASTE, and the read is NOT user-initiated — directly contradicting the scene's repeated P1 comments (lines 106-118, 459-463, 578-590) and surfacing the iOS 'pasted from X' banner the comments claim to avoid. Codex was right that the .clipboardUpdated path is a non-explicit bypass; the deeper cause is the still-active poll, not just the event handler. Recommendation: for the clipboard level, gate the auto-poll off (or drop the .clipboardUpdated->checkPassword path here) so the visible PASTE control is the only solve path; keep the GameRootView:241 fallback button as the no-hardware route. Low player impact (puzzle still completes), so polish.
- **L13 WiFiScene — hintText() is a single static line and points to 'Control Center' which can mislead** 
  - `Level13_WiFi.swift:927-929` · raised by: claude,gemini,kimi
  - The struggle->hint pipeline now fires (already-fixed above), but hintText() returns one undifferentiated line 'Toggle WiFi in Control Center' for both the ON-to-cross-chasm and OFF-to-climb-wall beats, and names Control Center even though the in-scene mechanic is the real device WiFi/accessibility toggle. Real but low impact. Recommend: split via difficultyHintDidShow()/struggleCount-aware text (e.g. first 'Turn WiFi ON to build the bridge', later 'Drop the signal to climb past the wall').
- **L13 WiFiScene — WiFi-ON stepping stones / OFF-step render at 0.3 alpha — load-bearing pieces read as decoration on first encounter** 
  - `Level13_WiFi.swift:516-517,790,802` · raised by: claude
  - Grounded: inactive wifiOn/wifiOff platforms are set to alpha 0.3 and the antenna/slash icons are scaled 0.5 (lines 495-501). The stones ARE the only bridge across the 232pt chasm, so a first-timer can't tell they're platforms vs the decorative signal art. Not a softlock (the mechanic still works once understood) but a genuine first-encounter legibility gap. Recommend ~0.5-0.6 alpha + a dashed/ghost fill for the inactive state and larger icons.
- **L14 FocusModeScene — Visible 'CAN'T DO THIS?' fallback button spoils that this is a toggle, not a system-state puzzle** 
  - `Level14_FocusMode.swift:649-690 (createDNDToggleButton, always shown)` · raised by: codex,claude,gemini
  - Legit design tension: the always-present fallback (plus the two bare moon HUD dots gemini/claude found ambiguous) tips the hand before the player discovers the real iOS Focus mechanic. Recommendation: gate the CAN'T DO THIS? button behind first struggle (reveal after a death or ~15s), matching the earned-hint cadence the level already uses elsewhere. Note it is the deliberate anti-softlock affordance, so keep it — just delay it.
- **L14 FocusModeScene — iPad interior climb is a chain of max-budget (130pt H + ~one-tier V) diagonal hops with one-fall-to-floor reset** 🆕
  - `Level14_FocusMode.swift:330-358 (strict ±105 alternation), :939-946 (handleDeath respawn at floor)` · raised by: kimi,adjudicator
  - Every interior rung strictly alternates ±composedColOffset, so consecutive rungs are 210pt center-to-center; with width-80 rungs the edge-to-edge gap is exactly 130 (== hard cap maxJumpableGap) AND simultaneously a ~one-tier rise, i.e. the hardest combined-vector jump in the game, repeated up the whole column, with hazards bobbing over each rung and a full reset to tier-0 on any miss. Within budget (not a softlock) but punishing for a teaching level. Recommendation: widen the alternating rungs to 90-100 (drops gap to ~110-120) or reduce composedColOffset to ~95 to ease the diagonal.
- **L15 LowPowerScene — No t=0 teaching of the POWER-button -> gravity link (bidirectional toggle undertaught on first encounter)** 
  - `Level15_LowPower.swift:664-691 (instruction panel), 886-888 (hintText)` · raised by: claude,codex,kimi,gemini,deepseek
  - Genuinely present: the t=0 panel ('THE BATTERY IS DYING / EVERYTHING GETS LIGHTER WHEN I LET GO') is atmospheric and never links the bottom-right POWER button to gravity, and the hardest idea (OFF for the narrow drop, ON for the chasm) is untaught until the struggle-gated hint. NOT a softlock: notePlayerStruggle() fires per death (line 871), notePlayerProgress() resets on first low-power engage (line 766), and the BaseLevelScene 22s wall-clock fallback (BaseLevelScene.swift:714-718) both surface hintText(), which names the button location and both toggle directions precisely. Recommendation: add a one-time diegetic cue near the POWER button (or on the chasm's first death) so the button->gravity link is discoverable a beat earlier without spoiling the reversal; low priority since the escalation already prevents a stuck state.
- **L21 DeviceNameScene — 5s name fallback can fire before the player registers the device-name was the point** 
  - `Level23_DeviceName.swift:126-132, 163-171` · raised by: codex
  - On simulator / no Local-Network-permission, the .deviceNameRead event may not arrive and the 5s fallback resolves to 'PLAYER' (or a parsed owner), so the 'the OS knows your real name' moment can quietly degrade. It's a deliberate anti-softlock net (correctly guarded by nameReceived) and the level stays completable, so this is polish only. Codex's suggestion (gate the fallback behind an explicit 'name unavailable' beat) would preserve the device-feature moment; optional.
- **L22 VoiceCommandScene — Bridge 5s auto-retract has no visual warning and can strand a hesitating player mid-chasm** 
  - `extendBridge() lines 753-758, retractBridge() lines 764-775` · raised by: claude
  - Real: the 5s retract fires on an invisible clock; a first-timer who walks slowly after BRIDGE falls to the death zone with no telegraph. Not a softlock — respawn works and the struggle/no-progress hint escalates — so polish. Recommend fading the bridge alpha as it nears retraction or a brief 'BRIDGE HOLDING' cue. Note this compounds the new FLY-gate finding above; both are downstream of the same transient-retract design.
- **L24 StorageSpaceScene — First-encounter: tapping CAN'T DO THIS? before arming does nothing visible** 
  - `Level24_StorageSpace.swift:932-951` · raised by: deepseek,codex,claude,gemini
  - A pre-arm purge already gets feedback: warning haptic + black vignettePulse + flashTerminalHint() (terminal glow double-pulses) — it points the player back at the terminal. It's adequate but subtle; the panel never explains WHY nothing happened. Optional polish: a one-line 'ARM THE TERMINAL FIRST' toast on the rejected tap would close the loop. Low priority — intro panel + hintText already cover it.
- **L25 TimeOfDayScene — showFourthWall()/narrator re-fires on every CYCLE TIME tap (spam)** 
  - `Level25_TimeOfDay.swift:884-894, 669-683 (applyTimeMode -> showFourthWall each call) + handleGameInput:917-921` · raised by: kimi
  - Partially real, broader than reviewers saw. GlitchedNarrator.present() replaces the existing line cleanly (Narrator.swift:174-175) so there is NO node leak/stacking — but the whisper line and its typewriter animation DO restart on every mode change. Worse than the button case: with no override, the device clock posts clockTimeUpdate every 30s (TimeOfDayManager:23) and handleGameInput calls applyTimeMode with NO hour-change guard, so the whole mode is re-applied AND showFourthWall re-fires every ~30 seconds (and the secret-hour .boss line re-fires every 30s at real 3:33 AM). Cosmetically intrusive, not a crash. Fix: guard handleGameInput on `hour != currentHour` before re-applying, and present the fourth-wall aside at most once per mode-enter (e.g. only when the resolved mode actually changed).
- **L26 LocaleScene — iPad t=0 reads as a broken empty void — hidden staircase is alpha=0/non-solid so the vertical center is dead and the exit floats isolated top-right** 
  - `Level26_Locale.swift:385 (p.alpha = 0 on hidden stairs)` · raised by: claude,codex
  - On iPad the composed full-height climb's correct route is fully invisible until solved, so the launch frame shows spawn+wrong-cluster low, a tall blank band, and an isolated exit plateau at the ceiling — it reads as broken rather than 'a route waiting to be revealed.' The puzzle is still solvable and fair, but first-impression readability suffers specifically on the wide canvas. Fix: give hidden stairs a faint low-alpha ghost outline (keep categoryBitMask=.none so still non-solid) so the band reads as intentional. Phone layout is unaffected (overlapping narrow column hides the void).
- **L27 VoiceOverScene — First-encounter opacity: t=0 panel doesn't name the accessibility/VoiceOver fix; players may tap or hunt for a mic** 
  - `VoiceOverScene.swift:715-733 (panel), 979-994 (death>=2 nudge), 1010-1012 (hintText)` · raised by: claude,codex,gemini,kimi,deepseek
  - Unanimous, and partly true: the deliberately cryptic plaque ('named aloud') is intentional theming and the escalation IS wired — deathCount>=2 shows 'PHASE THE PATH IN FIRST', notePlayerStruggle()->hintText() explicitly names VoiceOver + the bottom-left button. So a stuck player is rescued within ~2 deaths. Residual gap is only the pre-first-death window. Low-cost win: have the death>=1 (not >=2) or a ~6s idle nudge point at the purple accessibility button by name. Polish, not a softlock.
- **L27 VoiceOverScene — iPad climb is a ~250pt centered zig-zag column on a 1024+pt canvas → large blank L/R margins read as underfilled** 
  - `VoiceOverScene.swift:337-352, 376-389 (dx ±58 around center)` · raised by: claude
  - Claude alone, and it's a genuine visual-fill regression vs the design goal, NOT a fairness/completability bug — vertical fill is correct (tier0..tier13 spans floor→ceiling). The ±58 column was a deliberate fix for an EARLIER 'climb stacks off-screen right under dead sky' bug (see comment 337-345), so widening must preserve edge-to-edge gaps <=130. Recommend widening dx toward ±180-220 and verifying gaps, OR accept the ribbon. Cosmetic-leaning polish.
- **L27 VoiceOverScene — Rapid VoiceOver on/off can leave real-stone surfaces mid-fade (alpha overlap between showRevealedState and dimRevealedState)** 
  - `VoiceOverScene.swift:823-826 (showRevealedState removeAllActions), 861-866 (dimRevealedState sets alpha directly, no removeAllActions)` · raised by: kimi
  - Kimi is right that an overlap exists, but partly mitigated: showRevealedState() already calls removeAllActions() on surface+glyph before its fades, and dimRevealedState removes decoyPulse by key. The residual is dimRevealedState setting real-stone alpha=1.0 WITHOUT cancelling an in-flight fadeAlpha(to:1.0,0.25) from a just-fired showRevealedState — a mid-flight fade can briefly override it. Self-corrects in <0.25s; real stones stay solid/collidable throughout (physics unaffected). Cheap fix: removeAllActions() on real surfaces at the top of dimRevealedState. Cosmetic flicker only.
- **L27 VoiceOverScene — didEnd ground-contact delayed setGrounded(false) can un-ground Bit mid-stand during fast stone-to-stone hops** 🆕
  - `VoiceOverScene.swift:956-961` · raised by: adjudicator
  - NEW: didEnd schedules setGrounded(false) after 0.05s (coyote-time idiom). If Bit leaves stone A and lands on B within that window, A's delayed action still fires setGrounded(false) after B's didBegin set it true, briefly mis-flagging airborne. This is the standard shared pattern across levels (not L27-specific) and the 0.05s window plus immediate didBegin re-grounding make a missed jump unlikely with the generous ±58 gaps here. Low player impact; flag only because the prompt asks for animation-vs-physics desync class. Not worth a per-level fix.
- **L28 AirDropScene — iPad finale + locked door are off-screen at spawn; signature mechanic never telegraphed** 
  - `Level28_AirDrop.swift:228-302 (buildComposedIPadLevel) + setupBit:545-547` · raised by: claude
  - Correct: the iPad course is camera-scrolled (installCameraFollow, worldWidth = composedWorldWidth) and the SHARE/door finale sits at tier 11 far right, so spawn shows only an empty switchback staircase. No persistent 'TRANSMISSION AHEAD' arrow or camera-pinned door preview exists. Recommend a small camera-anchored '→ TRANSMISSION' marker so the climb's payoff is visible from spawn. Real but low-stakes (level is still completable and the climb itself reads).
- **L28 AirDropScene — Share-sheet cancel leaves terminal with no explanation (no keypad, no status text)** 
  - `Level28_AirDrop.swift:564-579 (completionWithItemsHandler else-branch)` · raised by: codex,claude,gemini,deepseek
  - Grounded and NOT a softlock: on completed==false the SHARE button is never removed (only showKeyboard() removes it) so the player can immediately retry, and notePlayerStruggle() now fires to escalate the hint ladder — a later commit already added that struggle call. What's still missing is diegetic feedback. Recommend setting a terminal status like 'SHARE CANCELED — STILL ENCRYPTED' in the else-branch. Codex's exact suggestion stands; the other reviewers overstated it as a stranding bug, which the persistent button disproves.
- **L28 AirDropScene — Single hintText() dumps the full step-by-step solution instead of stepped nudges** 
  - `Level28_AirDrop.swift:973-975 (hintText) + BaseLevelScene.swift:744-750 (notePlayerStruggle gating)` · raised by: deepseek,claude
  - Partly real. Escalation IS gated (struggleCount>=2 && playtime>=8s in base notePlayerStruggle, plus a ~22s wall-clock fallback), so the full reveal is earned, not instant. But there is only ONE hint string and it spells out the entire loop including the keypad-decoy caveat. A two-stage ladder (first nudge: 'the terminal is the actionable object — try SHARE'; second: the current full text) would be fairer. Minor.
- **L28 AirDropScene — Instruction panel never points at the actionable SHARE button (first-encounter fairness)** 
  - `Level28_AirDrop.swift:471-523 (showInstructionPanel) + 412-417 (shareBreathe)` · raised by: deepseek,kimi
  - Mild and partially mitigated: the SHARE button has a forever-breathe pulse to pull attention (suppressed under Reduce Motion, with a VoiceOver label), and the t=0 panel + escalating hintText cover the gap. Still, the panel text ('TAKE ME SOMEWHERE I CAN') is indirect for a first-timer. The same first-stage-nudge fix above resolves this. Low priority — not a completability risk.
- **L29 TheLieScene — Long walk-back from fake exit to spawn has no mid-course confirming waypoint** 
  - `Level29_TheLie.swift:633-672 (GO BACK arrow + chevron, camera-pinned); platforms only shaken not removed at 609-617` · raised by: claude,codex
  - After reveal the player walks ~1000pt (iPhone) / ~1570pt (iPad) left to the spawn door. The '<< GO BACK' label + '<<<' breadcrumb are pinned to the camera (always visible), and the original platforms remain as footing, so this is NOT a softlock or dead corridor — it is partially mitigated already. Residual polish: a single mid-course world-space '<<' marker (or a brief re-glow of the real door) would confirm the return trip is intended. Claude/Codex's core 'is this broken?' worry is softened by the camera-pinned arrow. Nice-to-have.
- **L30 CreditsFinaleScene — handleExit fires BOTH base victory effects and a bespoke victory sequence — duplicated confetti/haptic/audio + a stray 'LEVEL COMPLETE' marquee over the fake-out** 
  - `Level30_CreditsFinale.swift:937 handleExit() / 695 playVictorySequence()` · raised by: kimi,codex
  - handleExit() calls succeedLevel() (BaseLevelScene:508→playVictoryEffects() adds confetti, pops 'LEVEL COMPLETE', fires victory haptic/audio/flash/slow-mo) and THEN playVictorySequence() which independently adds its own confetti + HapticManager.victory + AudioManager.playVictory + flash + slowMotion. Effects double up and the generic base 'LEVEL COMPLETE' popText competes on-screen with the bespoke 'Y O U W I N' fake-out. Not a softlock: the two slowMotion calls share withKey:'slowMotion' so the second replaces the first (speed cleanly restores to 1.0 after 1.0s), and updatePlaying halts once state is .succeeded. Kimi was right about the root cause. Recommend: drop the redundant juice from playVictorySequence (or skip popText/confetti in playVictoryEffects for this level) so only the bespoke finale plays.
- **L31 FlashlightScene — iPad walk-by-one backfill can produce a 2-tier first jump at count=16** 🆕
  - `Level31_Flashlight.swift:497-503,125-129` · raised by: adjudicator
  - The defensive backfill loop (497-503) stops at i>=1, so it can raise tiers[1] to tiers[2]-1 without re-checking tiers[0] (pinned to 0), yielding a floor->tier-2 opening jump. Reproduces ONLY at ipadTierCount=16, which needs band>=1275pt (canvas height ~1515pt+). Realistic iPads top out at count=14 (12.9in, band ~1082) where the rule is clean (verified: counts 10/11/12/14 produce zero bad rises and a reachable finale). Unreachable on shipping hardware, so harmless today; worth a one-line guard (also clamp tiers[1]<=1) only as future-proofing if larger canvases appear.
- **L32 MultiTouchScene — Single exhaustive hint instead of a graduated 2-step nudge** 
  - `Level32_MultiTouch.swift:1335-1337 hintText()` · raised by: claude,kimi
  - The only genuine survivor: the safety-net fires one fully-spoiling hint rather than escalating ('try holding two glowing pads at once' -> 'keep them held while you walk Bit through'). Player is never stranded (gets full answer in ~22s), so this is taste/polish, not a fairness gap. Optional: override difficultyHintDidShow or add a soft first-nudge whisper before the full reveal. Low priority.
- **L32 MultiTouchScene — Two fingers on the same pad -> one lifting deactivates the pad while the other still holds it** 🆕
  - `Level32_MultiTouch.swift:868-875 (trackedTouches[touch]=index) + 897 (deactivatePlate on first end)` · raised by: adjudicator
  - trackedTouches maps each touch to a plate index with no per-plate refcount. If two touches both land within 38pt of the same pad, both map to index i; when the FIRST lifts, deactivatePlate(at:i) flips isActive=false even though the second finger is still on it, and evaluatePlateGroups may visually close a not-yet-latched gate. Self-inflicted (requires deliberately stacking two fingers on one ~28pt pad) and fully recoverable (re-press), and completed gates latch open so it never softlocks. Minor polish only; a small per-index hold count would harden it if touched later. Not worth a dedicated fix.

### ⚪ COSMETIC

- **L0 BootSequenceScene — iPad boot-log stranded top-left, empty lower/right void** 
  - `Level0_BootSequence.swift:85 bootTextContainer.position = (40, topSafeY-70)` · raised by: claude
  - Real but cosmetic-only: the anchored node is the NON-interactive boot LOG; the interactive UI (title/bar/handle/character) is correctly recentered to origin in revealMainUI (:209-213) once the camera moves to zero. On iPad the 5.5s log reads top-left with empty canvas, but nothing playable is stranded and there's no fairness/completability impact. Optional polish: center bootTextContainer.x on iPad. Lowest priority.
- **L0 BootSequenceScene — Idle-nudge wiggle restore skipped if drag interrupts mid-wiggle** 🆕
  - `Level0_BootSequence.swift:271-280 wiggle ends with .run restore; :487 removeAllActions()` · raised by: adjudicator
  - touchesBegan calls progressHandle.removeAllActions(), which can cancel the wiggle before its final `.run { position.x = baseX }` restore, leaving the handle up to ~16pt off baseline. Harmless: scale is explicitly reset (:488), progress is driven by the clamped drag (monotonic, only increases), and the player's own drag immediately repositions the handle. Net 0 wiggle so an uninterrupted nudge self-corrects anyway. Cosmetic at most; optional to compute restore from a captured baseX outside the action.
- **L0 BootSequenceScene — Foundation glitchTimer keeps firing while backgrounded (not invalidated on resign-active)** 🆕
  - `Level0_BootSequence.swift:301-309 startAmbientGlitches; :58 invalidate only in willMove` · raised by: adjudicator
  - glitchTimer is a repeating Foundation Timer invalidated only in willMove(from:)/deinit/completeBootSequence, not on app-background. While backgrounded it may still tick and add auto-removing flash nodes via triggerMicroGlitch. No crash, no leak (nodes self-remove, guarded by !bootComplete), purely a tiny off-screen waste. Cosmetic; would be cleaner as an SKAction (pauses with the scene) but not worth a fix on its own.
- **L1 HeaderScene — drawCables() fully implemented but never called** 
  - `Level1_Header.swift:361-396` · raised by: kimi
  - Confirmed dead code — drawCables is defined but setupBackground (and nothing else) calls it. Harmless. Recommendation: delete it, or wire it into setupBackground if the hanging cables were intended decor.
- **L1 HeaderScene — Magic numbers / dense layoutXScale-layoutYScale math should be named constants** 
  - `Level1_Header.swift:16,40-42,198-247` · raised by: gemini,kimi
  - Maintainability only — the values are heavily commented and the invariants (gap<=130, rise<=85) are clamped at runtime (BaseLevelScene.maxJumpableGap/maxJumpableRise). I simulated the iPad serpentine across 1024x1366 / 820x1180 / 834x1194: worst forward hop is exactly 130pt gap at 83pt rise (within caps) and right→left hops overlap in X, so reachability holds. No functional bug; refactor is optional.
- **L2 WindBridgeScene — iPad wind gust indicator lines overshoot the finale chasm onto/past the exit bank** 
  - `Level2_Wind.swift:824-843,1085-1102 (setupWindVisuals / animateWind)` · raised by: deepseek
  - REAL: the 8 gust lines are spaced by 25*layoutXScale from absolute chasmStartX, but layoutXScale scales with width while the iPad chasm is a fixed 235pt. They extend ~68pt (mini) to ~182pt (12.9) past chasmEnd, drifting over the exit bank. These are decorative non-physics indicators, so it is purely visual — no fairness/reach impact. Quick fix: on isWideCanvas space the 8 lines across (chasmEndX-chasmStartX)/8 instead of 25*layoutXScale so they stay inside the actual finale chasm.
- **L2 WindBridgeScene — Dead code: isCompactPhoneLayout (unread), drawHangingVibrationPickup (uncalled), lastMicLevel (write-only)** 
  - `Level2_Wind.swift:26-28,436-470,262/1035` · raised by: deepseek
  - REAL but cosmetic. isCompactPhoneLayout (26) is never read; drawHangingVibrationPickup (436) is never called; lastMicLevel (262) is assigned at 1035 and never read. Safe to delete all three; no behavioral effect. Cleanup only.
- **L2 WindBridgeScene — Magic numbers / hardcoded iPad gate / dense file; externalize layout** 
  - `Level2_Wind.swift:90-234` · raised by: gemini,deepseek,kimi
  - REAL maintainability nit: isWideCanvas threshold (h>1000 && w>600) and many inline column constants make this a long, dense file. Functionally correct and consistent with the other composed-iPad levels' style. Pure refactor; no player impact. Optional.
- **L3 StaticScene — Hardcoded 'Menlo-Bold'/'Menlo' font names instead of VisualConstants.Fonts** 
  - `Level3_Static.swift:748,1007,1014 vs VisualConstants.swift:65-66` · raised by: deepseek,gemini
  - The literals exactly equal VisualConstants.Fonts.main ('Menlo-Bold') / .secondary ('Menlo'), so rendering is correct — this is a token-consistency/maintainability nit only. Swap to the token if touching the file; not ship-blocking.
- **L6 BrightnessScene — iPhone t=0 opening tease caption can sit on/near the top of the climb column** 
  - `Level6_Brightness.swift:229-234 (band math) vs :891 (usableTop = layoutTopY - 170)` · raised by: claude
  - Minor and cosmetic. The compact tease band bottom is layoutTopY-168 while the climb's usableTop is layoutTopY-170 — only ~2pt of clearance, so on some renders the transient 2.8s caption can crowd the topmost platform/exit. The wrap + backing-plate logic is otherwise correct. Not a fairness or completability issue (auto-fades in <3s). If touched, lift bandBottom a few pt or shrink fontSize to guarantee separation from the climb top.
- **L7 ScreenshotScene — Unused designWidth constant** 
  - `Level7_Screenshot.swift:88 private let designWidth: CGFloat = 820` · raised by: kimi
  - Confirmed dead — declared and never referenced. Harmless. Delete on next cleanup pass.
- **L7 ScreenshotScene — Global screenshot gesture burns screenshotCount during the iPad climb before the finale** 🆕
  - `Level7_Screenshot.swift:992-999 freezeBridge increments screenshotCount unconditionally; 1154-1164 handleGameInput` · raised by: adjudicator
  - On the iPad climb the screenshot gesture is global, so a player who screenshots early (off-screen from the finale bridge) still increments screenshotCount and triggers the flash/haptic/timer. By the finale the freeze can already be at the 1.5s floor. Not a softlock (1.5s still > 0.9s cross) and screenshotCount resets on death; arguably intended (the OS gesture is global). Could optionally only escalate when the bridge is near-viewport. Very low impact.
- **L8 DarkModeScene — Cluster (REST-companion) ledge uses alwaysW(130) though comment calls it a 'wide ledge'** 
  - `Level8_DarkMode.swift:703 .cluster solid(...,w: alwaysW...)` · raised by: kimi,codex
  - Minor: the rest beat is a same-tier pair — cluster(130) + rest(170). Both exist and the flat hop between them is a trivial 50pt gap, so gameplay is unaffected; it only slightly under-reads as the intended 'wide breath' pause. Optional: bump cluster to restW for visual symmetry. Cosmetic.
- **L9 TimeTravelScene — composedWorldWidth math: courseLeft = leftMargin - 80 - leftMargin (= -80) contradicts comment** 
  - `Level10_TimeTravel.swift:553-555` · raised by: kimi
  - Real but benign: max(0, -80)=0 so the world spans x=0..courseRight, FULLY including the left scenery margin and base pad (wider, not narrower). The 'intended' value (70) would actually CHOP 70pt off the left. Runtime behavior is correct; only the comment/expression is misleading. Optional cleanup: 'let courseLeft = leftMargin - 80' + keep max(0,..). No player impact.
- **L9 TimeTravelScene — Tree-stage threshold logic duplicated verbatim in applyTimePassage and handleGameInput** 
  - `Level10_TimeTravel.swift:1074-1083 vs :1448-1457` · raised by: kimi
  - Real maintainability nit (the .timePassageSimulated debug path mirrors applyTimePassage's 5/15/30s ladder). Extract a single stageFor(secondsAway:gameYears:) helper. No gameplay effect; not worth a risky change pre-ship.
- **L10 OrientationScene — Double-nested DispatchQueue.main.async when posting orientationChanged** 🆕
  - `OrientationManager.swift:51-55` · raised by: adjudicator
  - Harmless code smell: the orientation post is wrapped in two nested DispatchQueue.main.async, deferring the event by two extra runloop hops. No functional impact (the event still fires, mechanic works, faceUp/faceDown/unknown are correctly filtered and an initial state is sent). Collapse to a single async for clarity. Not worth a dedicated change unless touching the file.
- **L11 NotificationScene — drawFloorGrid floorY=140 ignores lifted iPad floor (grid floats below gameplay)** 
  - `Level11_Notification.swift:238` · raised by: kimi
  - Correct but trivial: the decorative grid (zPosition -15, alpha 0.3, scene-anchored) is hardcoded at y=140 while the iPad gameplay floor is at groundY≈126 and the climb spans far above. It is pure background decoration, behind everything, and on iPad it doesn't even camera-scroll. No gameplay or fairness impact. Lowest priority.
- **L12 ClipboardScene — clipboardScanLabel is dead storage — declared, never assigned or read** 
  - `Level12_Clipboard.swift:24` · raised by: kimi
  - private var clipboardScanLabel: SKLabelNode? is never written or read anywhere in the file. Harmless dead state; delete it. kimi correct.
- **L13 WiFiScene — Download/SIGNAL bar is cosmetic but LEVEL-GUIDE says completing the download unlocks the final section** 
  - `Level13_WiFi.swift:660-675 / LEVEL-GUIDE.md:138` · raised by: codex,kimi
  - Code is internally honest: updateDownloadBar (666-668) comments it is purely cosmetic and handleExit (916) succeeds with no downloadCompleted gate; succeedLevel is idempotent. The in-game label only ever shows 'SIGNAL: STRONG/LOST' — it never tells the player to finish a download, so there's no in-game false objective. The mismatch is solely with LEVEL-GUIDE.md:138 ('Complete the download ... to unlock the final section'). Fix the doc (or rename the bar), not the level logic. Reviewers were right that the guide is stale; wrong that it misleads the player at runtime.
- **L13 WiFiScene — Stale didEnd delayed setGrounded(false) can briefly false-unground when walking between adjacent stones** 🆕
  - `Level13_WiFi.swift:897-905` · raised by: adjudicator
  - Hunted the runtime/state-edge class. didEnd schedules an unconditional 0.05s setGrounded(false); if a new didBegin (next stone) re-grounds in that window, the stale closure still fires false. BUT isGrounded is a plain bool (not a contact counter, so no underflow), PlayerController re-sets coyoteTimer every grounded frame and has a jump buffer (PlayerController.swift:74-89,112), and clearGroundedIfStandingOn handles the real de-solidify case immediately. Net player-visible impact is negligible and the pattern is shared base infra, not L13-specific. Logged for completeness only; not worth a fix here.
- **L14 FocusModeScene — Focus activation does not call notePlayerProgress() -> hint timer not reset at the key realization** 
  - `Level14_FocusMode.swift:800-848 (updateFocusState)` · raised by: codex
  - Minor: enabling Focus is the puzzle's solve moment but doesn't reset the no-progress/struggle timer, so a hint could still fire moments after the player already figured it out. Harmless (the door also opens, ending the struggle). One-liner: call notePlayerProgress() inside updateFocusState when enabled becomes true. Low priority.
- **L15 LowPowerScene — Grounded state tracked with naive begin/end (no contact counter) — multi-contact desync** 🆕
  - `Level15_LowPower.swift:848-865 (didBegin/didEnd)` · raised by: adjudicator
  - L15 does NOT adopt the BaseLevelScene sharedGroundPlatform contact-counter pattern; it sets grounded=true on any ground begin and grounded=false 0.05s after any ground end. If the player ever contacted two ground bodies at once, leaving one would clear grounded while still standing on the other. In practice harmless on this level: platforms are well-separated (iPad zig-zag) or vertically stacked but spatially distinct (iPhone), the 0.05s delay buffers single-frame flicker, and PlayerController's 0.16s coyote window covers any transient. No player-facing impact; flagging only as a latent-pattern note, not worth changing.
- **L15 LowPowerScene — iPad spawn comment says '~35pt clear' but code uses +50; dead composedCourseExtent=0 scaffolding** 🆕
  - `Level15_LowPower.swift:703 (+50 vs '~35pt' comment), 487 & 722 (composedCourseExtent==0 camera guard)` · raised by: adjudicator,deepseek
  - Doc/code mismatch: setupBit spawns the iPad player at composedSpawn.y+50 (body-bottom ~23pt above tier-0 top — safe, just a slightly longer settle) while the comment claims it matches the ~35pt phone margin. Separately, composedCourseExtent is hardcoded 0 so the installCameraFollow guard at line 722 is permanently dead. Both are intentional/inert (the guard is retained as a documented future opt-in) and player-invisible; clean up the comment if touching the file, otherwise leave.
- **L21 DeviceNameScene — Identity fracture: filename Level23, header 'Level 23', but levelID index 21 and title 'LEVEL 21'** 
  - `Level23_DeviceName.swift:4, 142, 229; class DeviceNameScene` · raised by: kimi
  - File is Level23_DeviceName.swift and the doc header says 'Level 23', but levelID = LevelID(world:.world3,index:21) and the on-screen title is 'LEVEL 21', and inline comments mix both numbers. No runtime impact (the level plays as 21), but it makes bug-tracing error-prone. Recommendation: reconcile the filename/header/comments to the canonical index 21.
- **L21 DeviceNameScene — normalizedName mishandles trailing-apostrophe / smart-quote possessives ("James' iPhone", curly quotes)** 
  - `Level23_DeviceName.swift:179-195, 953-965` · raised by: gemini,kimi
  - Only the ASCII "'s " pattern is stripped. "James' iPhone" or a smart-quote ’s yields a label like "JAMES' IPHONE" instead of "JAMES". Purely a display-label aesthetic on the matched door; the level is still completable (the displayed name is matched to its own armed door, not parsed). Low priority; a small regex covering ’/‘ and trailing s' would clean it up.
- **L22 VoiceCommandScene — Fallback BRIDGE/OPEN/FLY buttons pinned at hardcoded y=50, ignoring bottomSafeY** 
  - `presentFallbackControls() line 931` · raised by: deepseek
  - Minor real cosmetic. Buttons are placed at screen y=50 regardless of the home-indicator inset; on devices with a tall bottom safe area they sit a touch low but the 30pt-tall buttons remain on-screen and tappable. Only appears on the no-mic fallback path. Recommend anchoring to bottomSafeY+something; low priority.
- **L24 StorageSpaceScene — armPromptLabel = panel.children.first as? SKLabelNode is always nil (dead field)** 
  - `Level24_StorageSpace.swift:622, 673` · raised by: deepseek
  - Correct: panel's first child is the bg SKShapeNode (line 648), so the cast yields nil and the armPromptLabel?.removeFromParent() guard at 622 is dead. Harmless because showArmFeedback runs once (armTerminal is guarded by !terminalArmed). Just delete the unused field/line; no player impact.
- **L24 StorageSpaceScene — Stale comment at lines 514-516 references camera-follow that was removed** 
  - `Level24_StorageSpace.swift:513-516` · raised by: deepseek
  - Correct: the GUARD comment says the iPad wall is 'camera-followed' and at 'an absolute X far past size.width', but camera-follow was removed and the wall now sits at w/2+130 (on-screen). The code (the !isWideCanvas guard at 517) is still correct — only the rationale text is stale. Doc-only cleanup.
- **L25 TimeOfDayScene — Background clock icons hardcoded at x up to 560 scroll off-screen on iPad** 
  - `Level25_TimeOfDay.swift:97-106 (setupBackground, scene-child icons at fixed x, alpha 0.1, z -10)` · raised by: kimi
  - True but cosmetic only. The five alpha-0.1, z=-10 decorative clock faces are scene children at fixed x=80..560; on the camera-scrolled iPad course they scroll out of view and don't tile the wider canvas. They are pure background texture, not gameplay, so no fairness/completability impact. Optional polish: parent them to the camera (like the HUD/ghost decorations already are) or tile across composedCourseExtent.
- **L25 TimeOfDayScene — Contradictory instruction-panel width comments (300 vs 340)** 
  - `Level25_TimeOfDay.swift:599-615 (comment says 300, then 340; code uses 340)` · raised by: kimi
  - Stale comment only. The code uses width 340 (line 612); the earlier comment block at 599 still references a 300 value from a prior pass. Zero runtime impact — just reconcile the comment to avoid future-author confusion.
- **L26 LocaleScene — Revert-to-baseline after solving leaves signs permanently unscrambled (early-return makes revert branch unreachable)** 
  - `Level26_Locale.swift:670-672 vs 683-691` · raised by: kimi
  - Kimi is technically right: the early-return `if language == baseline { return }` preempts the `!changedFromBaseline && isUnscrambled` revert branch, so rescrambleTextOnly()/rescrambleWorld() never run on a same-case revert and the signs stay readable. BUT consequence is purely cosmetic: the solve path (changedFromBaseline && !isUnscrambled, requires language != baseline) is NEVER blocked, puzzleLatched keeps the correct route solid, and the exit stays reachable. So no softlock/fairness impact — it just means the post-solve atmospheric re-scramble doesn't fire. Optional polish: drop the early-return and let puzzleLatched drive text-only rescramble.
- **L28 AirDropScene — unlockDoor passes the wrong node to clearGroundedIfStandingOn (doorContainer vs doorBlocker)** 🆕
  - `Level28_AirDrop.swift:840-841 (clearGroundedIfStandingOn(doorContainer)) vs 453-457 (blocker body) + 942 (groundNode set)` · raised by: adjudicator
  - New, but no player impact. didBegin sets sharedGroundPlatform = groundNode(fromContact:) which returns the BODY-owning node — that's the child 'doorBlocker' (an SKNode added to 'door'), not 'doorContainer'. So clearGroundedIfStandingOn(doorContainer) can never match the guard sharedGroundPlatform === node and is a silent no-op. Harmless because the door is 120pt un-jumpable and is unlocked from the keypad while Bit stands on the platform, never on the door — Bit is never grounded on the door at unlock time. Cosmetic dead-code mismatch; pass doorBlocker (or door) if ever made standable.
- **L29 TheLieScene — hesitationCount inflates during the reveal cutscene, corrupting the TRUST readout** 
  - `Level29_TheLie.swift:813-824 (updatePlaying hesitation block); snapshot read at showPlayerAnalysis():694-735` · raised by: kimi,codex
  - updatePlaying keeps running through the whole reveal sequence (~4.8s of forced stillness: 0.8+3.0 in triggerFakeExitReveal, +1.0 before showPlayerAnalysis). triggerFakeExitReveal calls playerController.cancel() so Bit is held still, and standingStillTime accrues deltaTime every frame, adding ~2 phantom hesitations BEFORE the analysis snapshot reads hesitationCount. notePlayerProgress() in revealTruth resets struggleCount/noProgressTimer but NOT hesitationCount or standingStillTime. Net effect: the 'we measured your doubt' gotcha shows a near-deterministic inflated number, undermining the level's payoff. No gameplay impact. Cheap fix: guard the hesitation block with `guard !hasReachedFakeExit else { standingStillTime = 0; lastPlayerX = bit.position.x; return }` (or only count while control is active and Bit grounded). Codex/Kimi both right.
- **L29 TheLieScene — updateCamera lerp is frame-rate dependent (no deltaTime scaling)** 
  - `Level29_TheLie.swift:775-781 (updateCamera, newX = currentX + (targetX-currentX)*0.1)` · raised by: gemini
  - Fixed 0.1 smoothing per frame means the camera converges ~2x faster on 120Hz ProMotion than 60Hz — a feel inconsistency over the long right-then-left traversal, not a gameplay break (base update() already clamps dt to 1/30 so no resume spike). Gemini correct. Optional fix: frame-rate-normalize, e.g. factor = 1 - pow(0.9, deltaTime*60). Low priority.
- **L29 TheLieScene — Code-quality nits: hardcoded "LEVEL 29" title and unexplained 3.8s reveal duration** 
  - `Level29_TheLie.swift:95 ("LEVEL 29"), :548-553 (0.8+3.0 sequence)` · raised by: deepseek
  - Both real but purely cosmetic: the title could derive from levelID.index, and the wait durations are bare literals. No player-facing impact. Lowest priority; bundle into a style pass if ever touching the file.
- **L30 CreditsFinaleScene — Phone bugs scurry off the credit rung edges into mid-air (wrong column parity + offset magnitude + scurry range)** 
  - `Level30_CreditsFinale.swift:492 createBugs()` · raised by: gemini,deepseek,kimi
  - Grounded the math: rung i_credit sits at x = w/2 ∓30 (zigzagOffset 30). createBugs maps bug i→platformIndex=(i*2)%10+1 then sets bug xOffset=±60 by platformIndex parity — which is the OPPOSITE parity to the rung's own side AND 2x the magnitude (60 vs 30), then adds scurryRange 50. Result e.g. platformIndex=1 (rung i_credit=0 at w/2−30, half-width 55 → right edge w/2+25) gets a bug centered at w/2+60, already 35pt past the edge, scurrying to w/2+110. Bugs visibly hover beside the boxes. Phone-only: the iPad placeBug() anchors bugs on platformCenter.x with ±40 scurry on 115-wide rungs and stays on-platform. Purely visual (bodies are non-dynamic, never fall) and the ladder is near-centered so it rarely intrudes on the jump arc — hence cosmetic, not fairness. Recommend: bug x = actual rung center, clamp scurry to rungHalfWidth − bugHalfWidth.
- **L31 FlashlightScene — tierNear strict < tie-break snaps stalactite x=2630 to the lower tier** 
  - `Level31_Flashlight.swift:516-523,533-545` · raised by: kimi
  - Real: x=2630 is exactly 90pt from both beat 12 (lower tier) and beat 13 (higher), and best only updates on d<bestD so the lower tier wins. But it does NOT affect fairness: gapFromFloor 175 puts the tip at tierY+195, ~104pt above a +91 jump apex from the lower tier, and the hazard sits over the gap the player passes UNDER. x=2050/2250/2440 are also equidistant pairs with the same generous clearance. Cosmetic authoring imprecision; fix by using <= only if you want the visual to hang from the tier you climb toward.
- **L32 MultiTouchScene — Plate-vs-jumpable-rung visual crowding on iPad (rungs overlap plate rings)** 
  - `Level32_MultiTouch.swift:631-636 (plate positions) + 488-510 (climb rungs)` · raised by: claude
  - On iPad the finale plate HUD (camera-children at zPosition 499-501) can visually overlap the composed climb rungs (scene-space zPosition 2) in places, which slightly muddies which dots are tappable HUD vs scenery. Purely cosmetic — plates are camera children and remain the touch targets regardless. Low priority readability nit only.
- **L33 AppReviewScene — Residual double-unlock race: button tap then .appReviewReturned within ~1.15s both reach unlockDoorFromOptionalReview** 🆕
  - `Level33_AppReview.swift:1311-1315 (handleGameInput) vs 1023-1037 (requestAppReview)` · raised by: adjudicator
  - exitUnlocked is only set in unlockExit ~1.15s after a tap (0.55s wait + 0.6s shatter wait). requestAppReview guards on !inLevelReviewButtonUsed, but handleGameInput(.appReviewReturned) guards only on !exitUnlocked, so if the in-scene VALIDATE ME tap fires first (sets inLevelReviewButtonUsed=true, removes fallback, calls unlockDoorFromOptionalReview) and the accessibility star posts .appReviewReturned in the same ~1.15s window, the event path re-enters unlockDoorFromOptionalReview → duplicate terminal lines, a second shatterPadlock burst, and a second unlockExit (double 'UNLOCKED' pop + double doorPulse key/physics enable). No crash, no softlock — unlockExit is effectively idempotent (re-adds keyed action, re-enables already-enabled physics). Requires hitting two mutually-exclusive affordances for the same action within ~1s, so extremely rare. Fix: add `guard !inLevelReviewButtonUsed` to the .appReviewReturned branch (line 1312) before it sets the flag, matching requestAppReview. One line.
- **L33 AppReviewScene — iPad framing leaves the entire lower ~40% of the canvas as empty dotted void below the ground line** 
  - `Level33_AppReview.swift:186-187 + drawIPadUpperBandDecor 234-280 + BaseLevelScene.swift:37-42` · raised by: claude,gemini
  - Confirmed math: gameplayVerticalLift(120,215) lifts groundY to ~0.42*canvas (≈534pt on a 1366 iPad), so the playfield sits at ~39% height and the band BELOW the ground line is empty (drawIPadUpperBandDecor only brackets ABOVE the ground, up to playableCeilingY). On a deliberately FLAT no-jump finale this is purely visual — zero impact on completability, gates, padlock-auto-break, or fairness; iPhone is untouched (lift==0). Lowest-priority survivor. Fix if polishing iPad: either lower the lift target (e.g. 0.30 so the ground sits in the lower third) or extend the decorative shaft pillars below the ground line. Cosmetic, not blocking.
- **L33 AppReviewScene — Generic 'LEVEL COMPLETE' marquee + confetti + slow-mo fires on the true finale before the game-complete cinematic** 🆕
  - `Level33_AppReview.swift:1195 (succeedLevel) + BaseLevelScene.swift:547-579 (playVictoryEffects)` · raised by: adjudicator
  - handleExit() calls succeedLevel(), whose base playVictoryEffects() pops 'LEVEL COMPLETE', confetti, and a 0.3x slow-motion right as L33 starts its bespoke walk-into-door → blackout → 'SYSTEM OVERRIDE COMPLETE' cinematic. So the finale momentarily shows a generic per-level 'LEVEL COMPLETE' card (and the slow-mo slightly drags the door-walk) before the intended game-complete sequence. No functional problem (no UI auto-advances on .succeeded — GameRootView ignores it), purely tonal/polish. Optional: have L33 record completion + set state without the generic marquee, letting the cinematic stand alone.

### n/a

- **L6 BrightnessScene — Grounded-state resync when a platform de-solidifies under Bit (and contact-end handling)** 🆕
  - `Level6_Brightness.swift:1598-1608 (visibility resync) + :1721-1739 (didEnd) + :1532` · raised by: adjudicator
  - Verified correct, no bug — noting it because it is the runtime/state-edge class the brief asked to scrutinize. When brightness drops and a platform under Bit loses its ground bitmask, updateSinglePlatform clears currentGroundPlatform and calls setGrounded(false); the inverse re-grounds via isBitResting(). currentGroundPlatform is a single weak ref (no contact COUNTER, so no underflow), and didEnd only clears it when the ending contact IS the current ground node, so landing on a new platform mid-transition does not spuriously un-ground Bit. Base update() clamps deltaTime to 1/30 and foreground-return re-posts brightness via configure(), so resume re-syncs cleanly. No softlock.
- **L14 FocusModeScene — Frozen finale patrols could wall off the door** 🆕
  - `Level14_FocusMode.swift:576-592 (two patrols), :385 (door at finale.x+40)` · raised by: adjudicator
  - Investigated and cleared: when Focus latches the gate open the two patrols are isPaused at arbitrary mid-sweep X, but two 24pt-wide spikes cannot cover the ~104pt finale span continuously, and Bit can hop a single frozen spike to reach the exit body [+120,+160]. Always completable. Not a bug — recording the analysis so it isn't re-raised.

## Per-level verdicts


### L0 — BootSequenceScene
*ship — 0 crash/softlock, no fairness blockers; escalation+iPad+IUO concerns already-fixed, 4 false-positives, 1 new polish (off-theme 18s generic hint panel)*

**Top actions:**
- Override hintText() in BootSequenceScene to return a drag-the-loading-bar specific string (e.g. 'Drag the white dot all the way right to boot.') so the inherited 18s base no-progress panel stops showing the off-theme 'Try using your device's features...' copy.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | No stuck-player escalation / idle-nudge missing | `Level0_BootSequence.swift:233-281 (scheduleIdleNudge/triggerIdleNudge) + :486 disarm` |
| real-unfixed | cosmetic | iPad boot-log stranded top-left, empty lower/right void | `Level0_BootSequence.swift:85 bootTextContainer.position = (40, topSafeY-70)` |
| false-positive | n/a | Redundant completion marking (succeedLevel + markCompleted) | `Level0_BootSequence.swift:644 succeedLevel(); :797 markCompleted(levelID)` |
| false-positive | n/a | force-unwrap randomElement()! can crash | `Level0_BootSequence.swift:324 [UIColor.cyan,.magenta,.yellow].randomElement()!` |
| already-fixed | n/a | IUO progressHandle/cursorNode nil-deref risk | `Level0_BootSequence.swift:476,500,522,534 guard let progressHandle` |
| false-positive | n/a | handleTutorialTouchMoved swallows all moved events | `Level0_BootSequence.swift:784-791` |
| false-positive | n/a | Upfront 'DRAG TO 100% TO BOOT' spoils the answer / zero discovery | `Level0_BootSequence.swift:119 boot message; :424 on-screen hint` |
| new | polish | Inherited 18s no-progress hint panel shows off-theme generic copy | `Level0_BootSequence.swift (no hintText() override) → BaseLevelScene.swift:704/:784 hintText() ?? "Try using your device's features..."` |
| new | cosmetic | Idle-nudge wiggle restore skipped if drag interrupts mid-wiggle | `Level0_BootSequence.swift:271-280 wiggle ends with .run restore; :487 removeAllActions()` |
| new | cosmetic | Foundation glitchTimer keeps firing while backgrounded (not invalidated on resign-active) | `Level0_BootSequence.swift:301-309 startAmbientGlitches; :58 invalidate only in willMove` |

### L1 — HeaderScene
*ship — 0 crash/softlock survivors; 1 real fairness gap (consumed-banner recovery is non-obvious), 1 polish (whisper contrast), 1 cosmetic dead code; 4 panel findings are false-positives or already-fixed*

**Top actions:**
- Gate banner consumption on scene acceptance: only set hasDropped=true once the scene confirms a bridge (or snap the banner back on a scene-rejected drop) so a near-miss drag can't strand the player with a vanished banner and only the non-obvious fallback button for recovery (Level1_Header.swift:646-671 + LevelHeaderHUD.swift:142-151).
- Add a faint dark backing plate to the GlitchedNarrator .whisper style so the t=0 cyan line reads against L1's white background (GlitchedNarrator.swift ~227).
- Delete the unused drawCables() (Level1_Header.swift:361-396) or wire it into setupBackground.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | Header-drag has no affordance → first-timers soft-lock | `LevelHeaderHUD.swift:44-117 (idlePulse breathing glow); GameRootView.swift:47-49 + Level1_Header.swift:96 (always-on dragHUD fallback)` |
| false-positive | n/a | Drop hit-test is dangerously permissive / dilutes the 'aha' | `Level1_Header.swift:646-671 (handleHeaderDrop dropInPlayBand/dropNearPit)` |
| new | fairness | Missed manual drop consumes the banner permanently (no re-show, non-obvious recovery) | `LevelHeaderHUD.swift:142-151 (hasDropped=true) + GameRootView.swift:44 (HUDLayer keyed on levelID)` |
| false-positive | n/a | hintText() immediately reveals the full solution with no escalation | `Level1_Header.swift:819-821 + BaseLevelScene.swift:744-750,714-718` |
| false-positive | n/a | Force-unwrapped bit/playerController would crash if make() returns nil | `Level1_Header.swift:5-6,571-576; BitCharacter.swift:55-61` |
| real-unfixed | cosmetic | drawCables() fully implemented but never called | `Level1_Header.swift:361-396` |
| real-unfixed | polish | iPhone t=0 whisper low-contrast (accent on white) and competes with spawning Bit | `GlitchedNarrator.swift:101,227 (.whisper uses Colors.accent, no backing plate) + Level1_Header.swift:109-112` |
| already-fixed | polish | One-time banner wiggle/pulse when the whisper fires to draw the eye | `LevelHeaderHUD.swift:112-117 (idlePulse repeatForever)` |
| real-unfixed | cosmetic | Magic numbers / dense layoutXScale-layoutYScale math should be named constants | `Level1_Header.swift:16,40-42,198-247` |

### L2 — WindBridgeScene
*ship — 0 real fairness/crash issues; iPad void already-fixed by confined-column rewrite; 3 false-positives, 4 cosmetic survivors (dead code + iPad gust overshoot), 1 worth a quick polish*

**Top actions:**
- Optional cosmetic: on iPad (isWideCanvas) space the 8 setupWindVisuals gust lines across (chasmEndX-chasmStartX)/8 from chasmStartX instead of 25*layoutXScale, so the decorative gusts stay inside the finale chasm instead of overshooting the exit bank by up to ~182pt (Level2_Wind.swift:824-843, 1085-1102).
- Optional cleanup: delete dead members isCompactPhoneLayout (26-28), drawHangingVibrationPickup (436-470), and the write-only lastMicLevel (262/1035).
- Verification only (no code change): capture one portrait-iPad screenshot to confirm the confined-column climb now fills the frame and the round-1 'void' is visually closed.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | iPad renders flat phone strip with empty void above | `Level2_Wind.swift:90-332 (isWideCanvas, buildComposedIPadLevel, ipadComposedRoute)` |
| false-positive | n/a | Bridge collidable only above 10*visualScale -> weak breaths spawn invisible floor Bit falls through | `Level2_Wind.swift:687-702 (updateBridgePhysics)` |
| false-positive | n/a | Struggle path never escalates beyond generic notePlayerStruggle; soft-blow players left without targeted coaching | `Level2_Wind.swift:1196-1228 + BaseLevelScene.swift:744-750,704-718` |
| false-positive | n/a | Bridge physicsBody rebuilt on every segment-count change is brittle and can drop Bit during extension | `Level2_Wind.swift:687-725,1179-1192` |
| false-positive | n/a | Force-unwrapped optionals bit / playerController / bridge can crash | `Level2_Wind.swift:30-34,1107` |
| real-unfixed | cosmetic | iPad wind gust indicator lines overshoot the finale chasm onto/past the exit bank | `Level2_Wind.swift:824-843,1085-1102 (setupWindVisuals / animateWind)` |
| real-unfixed | cosmetic | Dead code: isCompactPhoneLayout (unread), drawHangingVibrationPickup (uncalled), lastMicLevel (write-only) | `Level2_Wind.swift:26-28,436-470,262/1035` |
| real-unfixed | cosmetic | Magic numbers / hardcoded iPad gate / dense file; externalize layout | `Level2_Wind.swift:90-234` |
| false-positive | n/a | Ambient room noise can extend the bridge before the player understands the mic mechanic | `Level2_Wind.swift:1032-1059 (handleGameInput .micLevelChanged)` |
| false-positive | n/a | First encounter relies on associating 'wind' with the microphone (cold-read leap) | `Level2_Wind.swift:874-955,957-1028,1222-1228` |

### L3 — StaticScene
*ship — 0 crash/softlocks; 1 new minor fairness edge-clip worth a 1-line fix, 1 inverse-cue polish; the panel's big iPad-void and missing-escalation findings are already-fixed or false-positives*

**Top actions:**
- Anchor the composed-iPad laser X to the gap's geometric center (between the platforms' NEAR edges) instead of the midpoint of their centers, so the TEACH laser hit-zone no longer overlaps the wide spawn deck's near edge by ~5pt (Level3_Static.swift:599-605).

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | iPad playfield hugs the floor with a large empty TV-frame interior above (vertical void) | `Level3_Static.swift:445-557 (buildComposedIPadLevel), 519-546 confined-column comment` |
| false-positive | n/a | No notePlayerStruggle() override, so deaths only hit the base fallback instead of escalating level-specific guidance | `Level3_Static.swift:1244 (handleDeath calls notePlayerStruggle), BaseLevelScene.swift:744-750` |
| false-positive | n/a | isWideCanvas check (height>1000 && width>430) wrongly excludes landscape iPad from the composed layout | `Level3_Static.swift:48` |
| false-positive | n/a | Rectangular laser hit bodies are not rotated to match arbitrary start/end beams (brittle) | `Level3_Static.swift:821-830 (createLaser hitZone), 676-677 / 696-699 (all beams share x)` |
| already-fixed | polish | Inverse-rule cue (dashed 4th laser + 'THIS ONE LISTENS DIFFERENTLY' placard) too subtle to read during motion | `Level3_Static.swift:730-781 (addInverseLaserClue)` |
| false-positive | n/a | iPhone half plays like a safe staircase (overlapping treads, tiny rises) rather than a laser-dodge | `Level3_Static.swift:362-369 (platformPoints), 695-701 (laser X band)` |
| false-positive | n/a | instructionPanel! force-unwrapped on addChild | `Level3_Static.swift:954 (assigned) / 970 (unwrapped)` |
| real-unfixed | cosmetic | Hardcoded 'Menlo-Bold'/'Menlo' font names instead of VisualConstants.Fonts | `Level3_Static.swift:748,1007,1014 vs VisualConstants.swift:65-66` |
| new | fairness | TEACH laser hit-zone overlaps the spawn platform's near edge by ~5pt on the wide-spawn / narrow-next pairing | `Level3_Static.swift:599-605 (composedLaserSpecs lx = midpoint of platform CENTERS), 552-553 (switchback x)` |

### L4 — VolumeScene
*ship — the headline 5-reviewer finding (isWideCanvas hardcoded false → dead iPad code) is STALE/already-fixed; iPad path is live and provably completable. Net: 0 real-unfixed of consequence, 1 minor polish, ~5 false-positives/already-fixed.*

**Top actions:**
- (Optional, polish) Replace the single static hintText() reveal with a 2–3 step context-sensitive ladder driven by notePlayerStruggle()/water state (vague quiet cue → 'the water is rising' cue → explicit Volume-Down), so the button name is the last rung rather than the first hint. Low priority — current behavior is already fair because the reveal is gated behind struggle/idle.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | isWideCanvas hardcoded to false → entire iPad composed-climb branch is dead code | `Level4_Volume.swift:89` |
| already-fixed | n/a | Idle-but-alive stuck player never earns the volume-button hint (escalation only on death) | `BaseLevelScene.swift:708-718` |
| real-unfixed | polish | hintText() is a full reveal / no graduated 'too loud' vs 'water rising' ladder | `Level4_Volume.swift:1607` |
| false-positive | n/a | Sleep-talk line 'lower the volume… please' spoils the mechanic before experimentation | `Level4_Volume.swift:157` |
| false-positive | cosmetic | KVO observer updates creature/indicator but skips updateWaterLevel(); relies on InputEventBus round-trip | `Level4_Volume.swift:1304-1312` |
| false-positive | n/a | No-hardware fallback seeds currentVolume=0.15, making the hazard 'nearly solved' | `Level4_Volume.swift:1285-1292` |
| false-positive | n/a | waterHazardActive only true >0.85 while comment says 'Flood!' at >0.7 — player stands in deep water 0.7–0.85 without drowning | `Level4_Volume.swift:296-300` |
| false-positive | n/a | playerController is an implicitly-unwrapped optional | `Level4_Volume.swift:23` |

### L5 — ChargingScene
*ship-with-one-fix — 1 new iPad softlock (charging-at-launch), 5 false-positives, 3 already-fixed by the consensus commit, 1 minor polish*

**Top actions:**
- Fix the iPad already-charging-at-launch softlock: gate the t=0 auto-trigger behind Bit reaching the boarding platform on isWideCanvas (or spawn iPad Bit on the boarding platform / let .deviceCharging re-arm the plug pre-ride). This is the only player-impacting survivor.

| status | sev | finding | ref |
|---|---|---|---|
| new | crash-softlock | iPad softlock when device is already charging at level launch | `Level5_Charging.swift:160-164 (auto-trigger) + setupBit:709-713 (iPad spawn) + triggerPlugAnimation:859 (gated by !hasPlugArrived)` |
| already-fixed | n/a | "PLUG IN YOUR CHARGER" t=0 spoiler label gives the trick away on entry | `Level5_Charging.swift:166-175, 753-758, hintText:1222-1228` |
| already-fixed | n/a | handleDeath does not call notePlayerStruggle, so falls don't escalate the hint | `Level5_Charging.swift:1166` |
| false-positive | n/a | deltaTime spike on background-resume drops the sinking plug out of bounds | `BaseLevelScene.swift:697-698,720 + Level5_Charging.swift:1065,1079-1082` |
| false-positive | n/a | handleExit double-transition: succeedLevel() then a self-scheduled transitionToNextLevel() | `Level5_Charging.swift:1176-1186 + BaseLevelScene.swift:508-518,522-524` |
| false-positive | n/a | buildIPadClimb silently returns when padTierCount < 4, stranding wide screens with no exit | `Level5_Charging.swift:53,66-84,451` |
| false-positive | n/a | Carry deltaY breaks under a parent/worldNode transform; lastTrackedPlugY set too early | `Level5_Charging.swift:925-926,1091-1096` |
| false-positive | cosmetic | Magic wide-canvas constant (size.width > 430) instead of a form-factor helper | `Level5_Charging.swift:52-53` |
| real-unfixed | polish | didEnd unconditionally schedules setGrounded(false) even if another ground body still touches | `Level5_Charging.swift:1137-1151` |
| false-positive | cosmetic | Force-removed implicitly-unwrapped `floor`; dead `_ = startPlatformTopY` | `Level5_Charging.swift:999,541` |

### L6 — BrightnessScene
*ship — 2 real polish/fairness survivors (stuck instruction panel + hazards live on load), 3 false-positives (force-unwraps, flat-hintText, over-large max-brightness hitboxes), 1 cosmetic (iPhone t=0 caption), jump budget and grounded-resync verified clean*

**Top actions:**
- On scene load, compare the initial UIScreen.main.brightness against the ghost/0.6 threshold: if already past it, fade out the instruction panel and call notePlayerProgress() so returning/high-brightness players are not stuck with a permanent BRIGHTNESS tooltip (kimi's panel-stuck bug).
- Gate the sun + burn-zone hazard bitmasks so they stay disabled until at least one UV platform has solidified once (or the player has actively raised brightness), so a device that starts at 100% gets one clean teach/solidify beat before the burn ceiling can kill (codex/kimi).

| status | sev | finding | ref |
|---|---|---|---|
| real-unfixed | polish | Instruction panel never auto-dismisses if device enters above 0.6 brightness | `Level6_Brightness.swift:1668-1679 (dismiss guard) + :101 (initial read) + BrightnessManager.swift:24-26 (activate re-posts current brightness)` |
| real-unfixed | fairness | Sun/burn hazard active on load if device starts at/above 0.95 brightness, before any teach beat | `Level6_Brightness.swift:101-106 (configureScene seeds currentBrightness then updateBurnZones/updateMaxBrightnessSun) + :531-555 (sun hazard enable) + :344-376 (burn zones enable)` |
| false-positive | n/a | Force-unwraps on maxBrightnessSun!/screenFlash!/instructionPanel!/burnWarning!/sunIcon!/brightnessBar!/brightnessIndicator! | `Level6_Brightness.swift:331, 340, 473, 1383, 1429, 1431, 1457` |
| false-positive | n/a | hintText() returns a single flat string, so struggling players get no escalating guidance | `Level6_Brightness.swift:1784-1786 + BaseLevelScene.swift:744-750 (notePlayerStruggle), :702-718 (timer + wall-clock fallback)` |
| false-positive | cosmetic | Sun hazard 280x50 rect and burn-zone radius 40 (vs 35 visual) are larger than their drawn art | `Level6_Brightness.swift:522 (280x50 hazard), :292/:317 (burst r35 / hazard r40)` |
| real-unfixed | cosmetic | iPhone t=0 opening tease caption can sit on/near the top of the climb column | `Level6_Brightness.swift:229-234 (band math) vs :891 (usableTop = layoutTopY - 170)` |
| new | n/a | Grounded-state resync when a platform de-solidifies under Bit (and contact-end handling) | `Level6_Brightness.swift:1598-1608 (visibility resync) + :1721-1739 (didEnd) + :1532` |

### L7 — ScreenshotScene
*ship — 0 real fixes; the headline panel findings are already-fixed, the freeze-floor concern is already-fixed (1.5s, not 1.0s), and the two code-bug claims are false-positives. Only soft polish (iPad wayfinding, stale comments, single-shot hint) remains.*

**Top actions:**
- (optional polish) iPad wayfinding: seed a faint ghost-preview of the finale bridge or a directional cue so the upper-center canvas isn't dead-white at spawn and the player senses where the climb leads
- (optional polish) graduate the hint: soft "a screenshot pins a moment" nudge after death 1, explicit Side+Vol-Up combo after death 3, instead of one-shot full reveal
- (cosmetic) delete the unused designWidth constant and scrub the stale "1.0s freeze" comments at lines 1052/1122/968 to match the actual 1.5s floor

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | Duplicate panel both opening with "SOME MOMENTS REFUSE TO MOVE..." (discovery + instruction) | `Level7_Screenshot.swift:125 showDiscoveryPanel; grep shows no showInstructionPanel in this file` |
| false-positive | n/a | First-encounter unfair: instruction text doesn't tell players HOW to freeze the bridge | `Level7_Screenshot.swift:1251 hintText() + BaseLevelScene:744 notePlayerStruggle / 765 showDifficultyHintIfNeeded` |
| already-fixed | n/a | Shortest degraded freeze is only ~1.0s + grace, too tight for the 220pt chasm | `Level7_Screenshot.swift:962-975 currentFreezeDuration() default: return 1.5` |
| false-positive | n/a | Re-screenshotting while frozen resets frozenTimeRemaining but not the warning flicker, causing false blink | `Level7_Screenshot.swift:992-993 freezeBridge guard !isBridgeFrozen; 1157 cooldown guard` |
| false-positive | n/a | bridgeGrace drops the bridge while Bit is mid-air during the grace jump → unfair death | `Level7_Screenshot.swift:1045-1062 unfreezeBridge / 1084 dropBridge` |
| real-unfixed | polish | iPad: finale chasm/exit scroll off-screen at spawn; upper-center canvas reads dead-white | `Level7_Screenshot.swift:456 buildComposedIPadLevel; setupBit:955 installCameraFollow` |
| real-unfixed | polish | Hints don't escalate gradually — single full-answer reveal rather than soft-nudge-then-reveal | `Level7_Screenshot.swift:1216-1227 handleDeath (only notePlayerStruggle); 1251 hintText` |
| real-unfixed | cosmetic | Unused designWidth constant | `Level7_Screenshot.swift:88 private let designWidth: CGFloat = 820` |
| false-positive | n/a | bridgeSpanHalfWidth() adds a magic +30 to a center-derived half width | `Level7_Screenshot.swift:1076-1081 bridgeSpanHalfWidth` |
| new | cosmetic | Global screenshot gesture burns screenshotCount during the iPad climb before the finale | `Level7_Screenshot.swift:992-999 freezeBridge increments screenshotCount unconditionally; 1154-1164 handleGameInput` |

### L8 — DarkModeScene
*ship — 0 softlocks; iPad relentless near-max diagonals (polish) is the only survivor worth touching; 4 false-positives (shadow-enemy off-platform, hint-no-escalation, fallback desync, trapped-in-platform), 1 latent robustness nit, discoverability already-fixed*

**Top actions:**
- iPad only: relax the relentless near-max diagonal — widen solid/dual platforms ~15–20pt or drop pitch to ~185 so every beat isn't an 85pt gap + ~82pt rise with ~6pt landing clearance (Level8_DarkMode.swift:630-638).
- Harden the iPhone rest->door bypass-block so it doesn't silently depend on step==50: derive the door multiplier from a fixed apex margin (or assert step==50 on phone) so a future smaller/split canvas can't re-open the flip-skip (Level8_DarkMode.swift:439/526).
- Optional cosmetic: give the .cluster rest-companion ledge restW(170) so the 'wide breath' pause reads as intended (Level8_DarkMode.swift:703).

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | Invisible core action / discoverability of the OS dark-mode switch | `Level8_DarkMode.swift:1549 updateDiscoverabilityNudge + :1748 hintText` |
| real-unfixed | polish | iPad climb pins every beat near the combined jump ceiling (85pt gap + ~82pt rise simultaneously) | `Level8_DarkMode.swift:630 pitch=200 / :620 tierStep` |
| false-positive | n/a | iPhone shadow enemy patrols off the left edge of the light platform | `Level8_DarkMode.swift:1249 + :1285 patrol` |
| false-positive | n/a | hintText() never escalates — same full-spoiler string every time | `BaseLevelScene.swift:744 notePlayerStruggle / :765 showDifficultyHintIfNeeded` |
| false-positive | n/a | Fallback toggle desyncs game state from real system appearance | `Level8_DarkMode.swift:1574 applyAppearance / :1592 createFallbackToggle guard` |
| false-positive | n/a | Player can be permanently trapped if a dual platform solidifies around Bit's bounding box | `Level8_DarkMode.swift:893 setPlatformSolid / :539 death zone / :1722 playBufferDeath` |
| false-positive | n/a | forceDarkMode UserDefaults could be left in the wrong global state on abnormal exit | `Level8_DarkMode.swift:1739 onLevelSucceeded / :1754 willMove` |
| new | polish | iPhone rest->door bypass-block depends on step hitting its 50pt cap | `Level8_DarkMode.swift:439 step=min(50,riseBand*0.10) / :526 doorPlatformY` |
| real-unfixed | cosmetic | Cluster (REST-companion) ledge uses alwaysW(130) though comment calls it a 'wide ledge' | `Level8_DarkMode.swift:703 .cluster solid(...,w: alwaysW...)` |
| false-positive | n/a | Discoverability nudge accumulator immune to resume deltaTime spike | `Level8_DarkMode.swift:1551 timeWithoutAppearanceChange += deltaTime` |

### L9 — TimeTravelScene
*ship — 0 real fixes worth doing; 1 new low-pri fairness nit (regrow-under-feet), most panel findings already-fixed or intentional-by-design*


| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | No early/escalating hint; notePlayerStruggle never wired; stuck player waits ~22s | `Level10_TimeTravel.swift:1425 tickPreHint / :1537 handleDeath` |
| false-positive | polish | t=0 panel 'ALL THINGS TAKE THEIR TIME...' too vague; first encounter reads as 'wait in place' | `Level10_TimeTravel.swift:1018 showInstructionPanel` |
| real-unfixed | cosmetic | composedWorldWidth math: courseLeft = leftMargin - 80 - leftMargin (= -80) contradicts comment | `Level10_TimeTravel.swift:553-555` |
| real-unfixed | cosmetic | Tree-stage threshold logic duplicated verbatim in applyTimePassage and handleGameInput | `Level10_TimeTravel.swift:1074-1083 vs :1448-1457` |
| false-positive | n/a | Force-unwraps of freshly-created optionals (signNode!, clockDisplay!, instructionPanel!, saplingNode!, fullTreeNode!) | `Level10_TimeTravel.swift:878,923,720,1007,1246` |
| false-positive | cosmetic | isWideCanvas uses magic-number threshold (size.height>1000 && size.width>390) | `Level10_TimeTravel.swift:48` |
| false-positive | n/a | iPad misjump on the long staircase sends Bit back to the base pad | `Level10_TimeTravel.swift:513-524 route / verticalTier` |
| new | fairness | Backgrounding to upgrade the tree while standing on a lower branch drops Bit (foothold removed mid-stand) | `Level10_TimeTravel.swift:1179-1201 growTreeToStage` |
| false-positive | n/a | groundContacts contact-counter underflow / desync on death-respawn | `Level10_TimeTravel.swift:1505-1523 didEnd / 1539 playBufferDeath` |

### L10 — OrientationScene
*ship — 0 real fixes needed; 5 false-positives/already-fixed, 1 new polish-only item. Level is completable and fair on both device classes.*

**Top actions:**
- (Optional, polish) Tighten iPad framing so the flat course centers/fills edge-to-edge instead of a lower-weighted strip, and shift the iPhone worldNode right a few pt so the crusher/skull is fully on-screen — it is the visual that motivates fleeing right. Mechanic-neutral.
- (Optional, polish) Make updateCorridorPhysics() synchronous on gap change and animate only the decorative walls, eliminating the (currently unreachable) 0.5s body/visual desync window — a tidiness win, not a fairness fix.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | Explicit hint gated 18-22s behind a 5-7s crusher death (hint pacing too slow) | `BaseLevelScene.swift:744-750 notePlayerStruggle; Level9_Orientation.swift:1731 handleDeath calls notePlayerStruggle` |
| false-positive | n/a | groundContacts can underflow to 0 while Bit still rests on the floor (false-airborne) | `Level9_Orientation.swift:1697-1721 didBegin/didEnd refcount` |
| false-positive | n/a | updateWorldScale animates worldNode xScale/yScale over 0.5s; physics-body scaling can trap/erratically collide the player during rotation | `Level9_Orientation.swift:1471-1493 animated scale; 1505 isCrusherActive=!isLandscape` |
| false-positive | polish | updateCorridorPhysics dispatched async after 0.5s while walls animate — half-second visual/collision desync; non-animated path also starts with stale bodies | `Level9_Orientation.swift:1482-1498 wall .moveTo + asyncAfter updateCorridorPhysics; 1124 createCorridor calls it synchronously` |
| false-positive | polish | Demo-closer solution lives outside the touchscreen — a player who never rotates can dead-end at the paywall | `Level9_Orientation.swift:1766 hintText; 1346-1360 rotate-icon panel; 283 AccessibilityManager.registerMechanics([.orientation])` |
| real-unfixed | polish | iPad portrait wastes canvas — flat course marooned lower-left, upper/right read as empty grid; iPhone clips crusher/skull off left edge | `Level9_Orientation.swift:137-198 cacheIPadFramingIfNeeded lift; 367-491 drawIPadRightShaft; 300-302 phone worldNode pin` |
| new | cosmetic | Double-nested DispatchQueue.main.async when posting orientationChanged | `OrientationManager.swift:51-55` |

### L11 — NotificationScene
*Ship with one real fix — 1 NEW softlock (granted-but-banner-dismissed, no in-app recovery), 1 real iPad fairness/polish (door-1 + door-0 platform overlap), 1 real polish (static hint never names the GLITCHED sender), plus 1 first-encounter fairness speed-bump; 3 false-positives, hint-escalation already wired.*

**Top actions:**
- Fix the GRANTED-but-banner-dismissed softlock: on .notificationReceived for the genuine pending id, present the same tappable in-app faux notification used on the denied path (or clear the re-request guard once the notification has fired) so a missed/swiped banner is always recoverable in-app.
- Brand the genuine sender at first encounter: name 'GLITCHED' (and warn off 'SYSTEM') in the intro/instruction panel, or delay the decoy until after the first successful unlock, so the iPad decoy-before-genuine timing isn't an unfair first-time trap.
- iPad polish: nudge door 0 out of the spawn-pad/rung-1 footprint and door 1 out of the top-landing footprint so each locked door reads as a distinct shape and can't snag Bit mid-jump on unlock.
- Polish: branch hintText() on the failure mode (decoy-tap counter -> 'LOOK FOR THE GLITCHED SENDER, NOT SYSTEM') instead of one static sentence.

| status | sev | finding | ref |
|---|---|---|---|
| new | crash-softlock | Granted permission + banner dismissed without tapping = softlock (no in-app recovery) | `Level11_Notification.swift:994 handleGameInput / requestNotification:749` |
| real-unfixed | fairness | iPad decoy fires 1s before genuine; intro never names the GLITCHED sender (first-encounter fairness) | `Level11_Notification.swift:783 (decoy delay) / 680-699 instruction panel` |
| real-unfixed | polish | iPad door geometry overlaps adjacent platforms (door 0 into spawn pad/rung-1; door 1 into top landing) | `Level11_Notification.swift:394 (door0) / 430 (door1)` |
| real-unfixed | polish | Static hintText never names the GLITCHED-vs-SYSTEM choice or the dropped rung | `Level11_Notification.swift:1113 hintText()` |
| false-positive | n/a | Faux-notification hit-tested with nodes(at:) breaks under iPad camera-follow | `Level11_Notification.swift:1036` |
| false-positive | n/a | uiLayer.addChild(instructionPanel!) force-unwrap could crash | `Level11_Notification.swift:672` |
| real-unfixed | cosmetic | drawFloorGrid floorY=140 ignores lifted iPad floor (grid floats below gameplay) | `Level11_Notification.swift:238` |
| false-positive | n/a | Mechanic over-explained at t=0 | `Level11_Notification.swift:680-699 instruction panel` |
| false-positive | n/a | setGrounded(false) delayed clear on didEnd — contact-state desync risk | `Level11_Notification.swift:1081-1086 / BitCharacter.swift:884` |

### L12 — ClipboardScene
*ship — 1 real polish (auto-solve poll contradicts the level's own user-initiated-paste claim), 1 real cosmetic (dead var), 4 false-positives, 2 already-fixed by the safety-net/de-spoil work*

**Top actions:**
- Stop the clipboard auto-solve so the visible PASTE button is the real solve path: in the clipboard level, suppress the background poll's .clipboardUpdated->checkPassword auto-unlock (or skip the manager's string-read poll) so no non-user-initiated UIPasteboard.general.string read fires — this also honors the level's own P1 'paste from X' anti-banner claim. Keep the GameRootView fallback button intact.
- Delete the dead clipboardScanLabel property (line 24).

| status | sev | finding | ref |
|---|---|---|---|
| real-unfixed | polish | Background clipboard poll auto-solves the puzzle and contradicts the level's 'string read is user-initiated only' claim | `ClipboardManager.checkClipboard():46-62 + Level12 handleGameInput:652-661` |
| real-unfixed | cosmetic | clipboardScanLabel is dead storage — declared, never assigned or read | `Level12_Clipboard.swift:24` |
| false-positive | n/a | Literal answer GLITCH3D only appears in hintText() — first-timer can't know what to copy without the hint | `createTerminal():491-505, hintText():735-737` |
| already-fixed | n/a | Stuck-but-not-dying player never triggers hint escalation (struggle only increments on death) | `BaseLevelScene.updatePlaying:714-718 (lastProgressAt fallback)` |
| false-positive | n/a | Single spoiler hintText() returned on every call prevents graduated hints | `hintText():735-737 + BaseLevelScene struggle pipeline` |
| false-positive | cosmetic | iPad finale (terminal/PASTE/door/exit) off-screen to the right at t=0 — reads as 'staircase to nowhere' | `buildComposedIPadLevel:261-351 + installCameraFollow:136-140` |
| false-positive | n/a | doorBlocker! force-unwrap | `createLockedDoor():392-396` |
| false-positive | n/a | isWideCanvas hard-codes 1000pt height instead of base-class helpers | `Level12_Clipboard.swift:64` |
| false-positive | n/a | iPhone & iPad jump-reach / locked-door trap within budget | `createLockedDoor():370-399, buildComposedIPadLevel:300-338` |

### L13 — WiFiScene
*ship — 0 crash/softlock, 2 real polish (illegible 0.3-alpha load-bearing stones; non-escalating + Control-Center-pointing hint), 1 stale doc (LEVEL-GUIDE download claim), and 3 false-positives/already-fixed (notePlayerStruggle present, isWideCanvas gate intentional, finale-offscreen by design)*

**Top actions:**
- Render the load-bearing WiFi-ON stones and the WiFi-OFF step at ~0.5-0.6 alpha (not 0.3) with a dashed/ghost fill and larger icons so first-time players read them as platforms, not decoration (Level13_WiFi.swift:516-517,495-501)
- Make hintText escalating/beat-aware and stop pointing at 'Control Center' (Level13_WiFi.swift:927-929) — e.g. first 'Turn WiFi ON to build the bridge', then 'Drop the signal to climb past the wall'
- Update LEVEL-GUIDE.md:138 to remove the 'complete the download to unlock the final section' claim (the bar is intentionally cosmetic), or rename the bar to a pure signal-strength readout

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | handleDeath() does not call notePlayerStruggle() — repeated falls don't escalate the hint | `Level13_WiFi.swift:911` |
| real-unfixed | polish | hintText() is a single static line and points to 'Control Center' which can mislead | `Level13_WiFi.swift:927-929` |
| real-unfixed | polish | WiFi-ON stepping stones / OFF-step render at 0.3 alpha — load-bearing pieces read as decoration on first encounter | `Level13_WiFi.swift:516-517,790,802` |
| real-unfixed | cosmetic | Download/SIGNAL bar is cosmetic but LEVEL-GUIDE says completing the download unlocks the final section | `Level13_WiFi.swift:660-675 / LEVEL-GUIDE.md:138` |
| false-positive | n/a | isWideCanvas gate (height>1000 && width>430) is brittle / mis-handles split-view/compact iPad | `Level13_WiFi.swift:54` |
| false-positive | n/a | On iPad the finale trap + stones sit off-screen right until the camera scrolls (no preview) | `Level13_WiFi.swift:776,398-448` |
| new | cosmetic | Stale didEnd delayed setGrounded(false) can briefly false-unground when walking between adjacent stones | `Level13_WiFi.swift:897-905` |

### L14 — FocusModeScene
*ship — 0 crash/softlock survivors; the headline iPad-void and finale-lane fears are already-fixed/false-positive against current code; only real survivors are 2 polish items (max-budget diagonal climb, fallback-button spoiler).*

**Top actions:**
- Delay the 'CAN'T DO THIS?' fallback button (and consolidate/label the bare moon HUD dots) until first struggle so the real iOS Focus mechanic stays a discovery — keep it as the anti-softlock escape, just gate it (polish).
- Ease the iPad interior climb: widen alternating rungs to ~95-100pt or drop composedColOffset to ~95 so each hop isn't simultaneously the 130pt-horizontal AND one-tier-vertical max-budget diagonal (polish/fairness).
- Call notePlayerProgress() in updateFocusState when Focus turns on, so the hint timer resets at the solve moment (cosmetic one-liner).

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | iPad layout = bottom-right course with dead upper-left void | `Level14_FocusMode.swift:308-404 (composedRoute/buildComposedIPadLevel), :136-145 (no camera-follow)` |
| false-positive | n/a | Finale left landing lane only ~10pt, contradicting the ~50pt promise | `Level14_FocusMode.swift:579-582 (patrolSpecs)` |
| false-positive | n/a | calmOverlay!/exitBlocker! force-unwraps can crash | `Level14_FocusMode.swift:641 (calmOverlay!), :712 (exitBlocker!)` |
| false-positive | n/a | HUD parented to camera before installCameraFollow exists -> nil gameCamera | `Level14_FocusMode.swift:617-690 (createFocusIndicator/DND button), :136-145` |
| false-positive | n/a | notePlayerStruggle() never overridden -> only generic 18-22s fallback hint | `Level14_FocusMode.swift:943 (handleDeath calls notePlayerStruggle); BaseLevelScene.swift:744-750` |
| real-unfixed | cosmetic | Focus activation does not call notePlayerProgress() -> hint timer not reset at the key realization | `Level14_FocusMode.swift:800-848 (updateFocusState)` |
| real-unfixed | polish | Visible 'CAN'T DO THIS?' fallback button spoils that this is a toggle, not a system-state puzzle | `Level14_FocusMode.swift:649-690 (createDNDToggleButton, always shown)` |
| new | polish | iPad interior climb is a chain of max-budget (130pt H + ~one-tier V) diagonal hops with one-fall-to-floor reset | `Level14_FocusMode.swift:330-358 (strict ±105 alternation), :939-946 (handleDeath respawn at floor)` |
| new | n/a | Frozen finale patrols could wall off the door | `Level14_FocusMode.swift:576-592 (two patrols), :385 (door at finale.x+40)` |

### L15 — LowPowerScene
*ship — 1 real fairness-polish survivor (t=0 POWER-button discoverability, already safety-netted by hints), 5 false-positives, 0 crashes/softlocks; the physics gate and both layout paths are verified correct*

**Top actions:**
- Add a single one-time diegetic cue tying the POWER button to gravity on first encounter (e.g. a brief pulse/label near the button or a gravity-arrow flash on the chasm's first death), so the bidirectional toggle is discoverable one beat before the struggle-gated hint — the only real survivor, and low priority since the hint escalation already prevents a stuck state.

| status | sev | finding | ref |
|---|---|---|---|
| real-unfixed | polish | No t=0 teaching of the POWER-button -> gravity link (bidirectional toggle undertaught on first encounter) | `Level15_LowPower.swift:664-691 (instruction panel), 886-888 (hintText)` |
| false-positive | n/a | Always-visible manual POWER toggle 'undercuts the device-feature premise'; gate it behind isLowPowerModeEnabled availability | `Level15_LowPower.swift:559-589 (createLowPowerToggleButton), DeviceIntegration/PowerModeManager.swift:21-45` |
| false-positive | n/a | degradePlatformVisuals permanently mutates alpha/lineWidth and stacks / fails to restore on repeated toggles | `Level15_LowPower.swift:777-805 (degradePlatformVisuals OFF branch 797-803)` |
| false-positive | n/a | Finale depends on a 620 dy launch but BitCharacter applies only a 470 impulse; apex *150 divisor unvalidated | `Characters/BitCharacter.swift:848-854 (jump), Level15_LowPower.swift:178-189 (apex math)` |
| false-positive | n/a | iPad composed climb's same-tier beats overlap into a confusing flat run | `Level15_LowPower.swift:344-411 (beat plan + zig-zag X assignment)` |
| false-positive | n/a | Force-unwrapped IUOs (bit, playerController, batteryIndicator) risk a crash | `Level15_LowPower.swift:12-13, 29, 848-858 (didBegin uses bit)` |
| new | cosmetic | Grounded state tracked with naive begin/end (no contact counter) — multi-contact desync | `Level15_LowPower.swift:848-865 (didBegin/didEnd)` |
| new | cosmetic | iPad spawn comment says '~35pt clear' but code uses +50; dead composedCourseExtent=0 scaffolding | `Level15_LowPower.swift:703 (+50 vs '~35pt' comment), 487 & 722 (composedCourseExtent==0 camera guard)` |

### L21 — DeviceNameScene
*ship — completable on every device (no softlock); 1 new fragile-clamp/squeeze fairness-polish issue on iPhone bay3, ~4 false-positives, identity-naming cosmetic, spoiler is by-design*

**Top actions:**
- Fix the iPhone bay3 clamp: correct the wrong half-width math in setupBit (line 908-916 uses 11, real is 22 -> maxX is 368 not 379) and nudge worldWidth ~+12 or shift the rightmost slot/pillar a few pt left so Bit seats cleanly in bay3 instead of completing only via exit-body overlap while jammed on pillar2
- Reconcile the Level 21 vs 23 identity (filename/header/inline comments) to the canonical levelID index 21 to stop mis-tracing

| status | sev | finding | ref |
|---|---|---|---|
| new | fairness | iPhone bay3 reachability proof is numerically wrong; Bit squeezes against pillar2 but still contacts door3 exit | `Level23_DeviceName.swift:908-916 (setupBit clamp) + installBayPillars:553-564` |
| false-positive | n/a | Doppelganger can solve the puzzle / opens a door on a timer | `Level23_DeviceName.swift:679-741, 743-777` |
| false-positive | n/a | resolveFallbackName returns a non-uppercased raw string, inconsistent with normalizedName | `Level23_DeviceName.swift:163-170, 179-195, 921-965` |
| false-positive | n/a | resolvedFallbackRealX/DecoyX set in buildPhoneLevel but never updated after assignDoorIdentities | `Level23_DeviceName.swift:267-268, 472-473, 663-677` |
| already-fixed | n/a | No escalating hint chain; stuck players stall (hintText returns same line forever) | `BaseLevelScene.swift:200-218, 693-750; Level23_DeviceName.swift:1047-1071` |
| false-positive | polish | Final door bays are narrower than Bit's body, causing a physics squeeze that can trap the player | `Level23_DeviceName.swift:318, 458-466; BitCharacter.swift:57,75` |
| false-positive | cosmetic | Instruction + narrator spoil the device-name solution before the player discovers it | `Level23_DeviceName.swift:822-886` |
| real-unfixed | cosmetic | Identity fracture: filename Level23, header 'Level 23', but levelID index 21 and title 'LEVEL 21' | `Level23_DeviceName.swift:4, 142, 229; class DeviceNameScene` |
| real-unfixed | cosmetic | normalizedName mishandles trailing-apostrophe / smart-quote possessives ("James' iPhone", curly quotes) | `Level23_DeviceName.swift:179-195, 953-965` |
| real-unfixed | polish | 5s name fallback can fire before the player registers the device-name was the point | `Level23_DeviceName.swift:126-132, 163-171` |

### L22 — VoiceCommandScene
*ship — 1 real fairness fix worth doing (FLY gate vs transient bridge state, missed by all 5), 2 minor real polish items, 5 false-positives (incl. a wrong-file keypad "crash"), 0 crashes/softlocks*

**Top actions:**
- Latch FLY's prerequisite on a 'bridge has been extended at least once' flag instead of the transient bridgeExtended, so a player who crossed before the 5s retract isn't wrongly told to 'SPEAK BRIDGE AND OPEN FIRST' (activateFly line 803).
- Raise the iPhone locked-door height from the 90pt default to 107pt to match the iPad margin and close the ~1pt frame-perfect skip-over of the OPEN gate (buildPhoneLevel line 233).
- Telegraph the 5s bridge retract (fade the bridge as it nears retraction or a brief 'BRIDGE HOLDING' cue) so a hesitating player understands the mid-chasm fall instead of dying to an invisible clock (extendBridge lines 753-758).

| status | sev | finding | ref |
|---|---|---|---|
| new | fairness | FLY gate keys off transient bridgeExtended, which auto-retracts after 5s — a legitimately-crossed player gets the wrong 'SPEAK BRIDGE AND OPEN FIRST' rejection | `activateFly() line 803; retract at extendBridge() lines 753-758` |
| real-unfixed | polish | Bridge 5s auto-retract has no visual warning and can strand a hesitating player mid-chasm | `extendBridge() lines 753-758, retractBridge() lines 764-775` |
| real-unfixed | fairness | iPhone locked door keeps 90pt height (top ~+105) vs iPad 107pt — ~1pt over-clearance allows a frame-perfect skip on iPhone only | `buildPhoneLevel() line 233 (door at groundY+60, default height 90); iPad line 386 uses 107` |
| false-positive | n/a | Keypad node-name split-by-underscore will crash if the random code contains '_' | `no such code in Level21_VoiceCommand.swift` |
| false-positive | n/a | hintText() dumps the full command order immediately with no escalation; struggle only fed on death | `hintText() line 1123; BaseLevelScene notePlayerStruggle() lines 744-750, update() lines 703-718` |
| false-positive | cosmetic | JUMP alias for FLY can be triggered accidentally while experimenting aloud | `handleGameInput case FLY/JUMP lines 1020-1021; gate in activateFly() line 803` |
| false-positive | n/a | doorBlocker! force-unwrapped in createLockedDoor | `createLockedDoor() line 513 (doorBlocker assigned 509-512)` |
| false-positive | cosmetic | Instruction-panel fade relies on brittle //permissionContinueButton recursive poll that never self-terminates if the base renames the node | `permissionOverlayPresent line 697-699, showInstructionPanel poll lines 680-689` |
| real-unfixed | cosmetic | Fallback BRIDGE/OPEN/FLY buttons pinned at hardcoded y=50, ignoring bottomSafeY | `presentFallbackControls() line 931` |
| false-positive | n/a | No-mic fallback buttons reveal all command words and flatten the puzzle | `armFallbackTimeout() lines 884-907, presentFallbackControls() 912-939` |
| false-positive | n/a | iPad tier step ~83pt sits only ~2pt under the 85pt rise cap | `buildComposedIPadLevel() tierCount=14 line 321; verticalTier clamp BaseLevelScene line 104` |
| false-positive | n/a | bridgeExtended/doorOpened stay true after retract/open, could confuse a player who re-triggers | `extendBridge() line 732 guard, openDoor() line 778 guard` |

### L24 — StorageSpaceScene
*ship — 0 real crash/softlock, 1 minor polish survivor (pre-arm purge nudge), the rest already-fixed or false-positives (iPad void fixed, struggle-hint wired, cache-delete is intentional teardown)*

**Top actions:**
- Optional polish: when attemptPurge() is rejected for lack of arming (line 933-939), surface a brief 'ARM THE TERMINAL FIRST' toast so a player who taps CAN'T DO THIS? early understands why nothing dissolved — current haptic+vignette+glow-flash is good but silent on the reason.
- Trivial cleanup: delete the dead armPromptLabel field/assignment (lines 622,673 — always nil) and fix the stale camera-follow comment at lines 513-516. Doc/lint only, zero player impact.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | iPad renders as a diagonal void; terminal/junk/exit off-screen | `Level24_StorageSpace.swift:326-394, 845-864` |
| already-fixed | n/a | Deaths don't call notePlayerStruggle(), so stuck players get no faster help | `Level24_StorageSpace.swift:1017-1024` |
| false-positive | n/a | Junk blocks keep physics during 0.8s scatter and can collide with the player mid-air | `Level24_StorageSpace.swift:457-484, 868-894` |
| false-positive | n/a | removeCacheFile() in willMove deletes the cache prematurely / breaks Settings solve path | `Level24_StorageSpace.swift:1043-1050; StorageSpaceManager.swift:53-77` |
| real-unfixed | cosmetic | armPromptLabel = panel.children.first as? SKLabelNode is always nil (dead field) | `Level24_StorageSpace.swift:622, 673` |
| real-unfixed | cosmetic | Stale comment at lines 514-516 references camera-follow that was removed | `Level24_StorageSpace.swift:513-516` |
| false-positive | n/a | t=0 text spoils the objective by naming 'PURGE TERMINAL' | `Level24_StorageSpace.swift:828-840, 613-618` |
| real-unfixed | polish | First-encounter: tapping CAN'T DO THIS? before arming does nothing visible | `Level24_StorageSpace.swift:932-951` |
| false-positive | n/a | isWideCanvas 700pt threshold undocumented for in-between sizes | `Level24_StorageSpace.swift:81` |
| false-positive | n/a | Add an 'ARMED' green indicator on the terminal | `Level24_StorageSpace.swift:595-619` |
| false-positive | n/a | screenSpaceCenter marquee placement with no camera follow | `Level24_StorageSpace.swift:918; BaseLevelScene.swift:587-589, 278-280` |

### L25 — TimeOfDayScene
*ship — geometry/completability solid on both devices; 1 real fairness edge (enemy snap-on-day), 2 polish (30s clock re-fire spam + guard-not-centered on phone), the rest false-positives/already-fixed*

**Top actions:**
- Phone guard clarity: widen the phone GUARD (enemy 0, line 359) range to ~45 or shift its center right so the awake DAY sweep covers ALL of P2's top [220,310] — turns the forced jump from a position-dodgeable beat into an unambiguous must-sleep-it gate (the iPad guard already does this).
- Throttle the clock/narrator: add a `hour != currentHour` guard in handleGameInput (line 917-921) and present showFourthWall() only on an actual mode change, so the whisper/boss narrator stops re-firing (and re-running typewriter) every 30s from the device-clock tick.
- Soften the DAY-transition spike snap (applyDayMode line 691-701): ease the spike back to patrol.origin over ~0.15s and re-arm its .hazard mask only after it arrives, removing the one-frame teleport-onto-player that can deal a no-warning death.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | Hint only fires on death, not for a living/hesitant player | `BaseLevelScene.swift:702-718 (no-progress wall-clock safety-net)` |
| false-positive | n/a | Override persists and blocks the real clock from taking effect / not reset across attempts | `Level25_TimeOfDay.swift:919, 902-911` |
| real-unfixed | fairness | Enemy teleports to patrol origin on switch back to DAY, can hit player unfairly | `Level25_TimeOfDay.swift:691-701 (applyDayMode snap to patrol.origin)` |
| real-unfixed | fairness | Guard spikes sit on the left shoulder of P2, not centered over the only landing — puzzle may read as a timing/position dodge | `Level25_TimeOfDay.swift:359-363 (phone enemyData: guard center 250, range 35 -> sweep [215,285]) vs P2 span [220,310]` |
| real-unfixed | polish | showFourthWall()/narrator re-fires on every CYCLE TIME tap (spam) | `Level25_TimeOfDay.swift:884-894, 669-683 (applyTimeMode -> showFourthWall each call) + handleGameInput:917-921` |
| real-unfixed | cosmetic | Background clock icons hardcoded at x up to 560 scroll off-screen on iPad | `Level25_TimeOfDay.swift:97-106 (setupBackground, scene-child icons at fixed x, alpha 0.1, z -10)` |
| false-positive | n/a | Force-unwrap of overrideMode! at line 910 | `Level25_TimeOfDay.swift:902-910` |
| false-positive | n/a | Always-visible CYCLE TIME button makes the real-clock level trivially solvable / button easy to miss | `Level25_TimeOfDay.swift:563-594, 1017-1019 (hintText names the button)` |
| false-positive | n/a | Phone P1->P2 forced gap is right at the 130pt budget with little margin | `Level25_TimeOfDay.swift:174-182 (P1 span [10,90], P2 span [220,310] -> open gap 130)` |
| real-unfixed | cosmetic | Contradictory instruction-panel width comments (300 vs 340) | `Level25_TimeOfDay.swift:599-615 (comment says 300, then 340; code uses 340)` |
| false-positive | n/a | isWideCanvas / threshold constants are arbitrary hardcoded magic numbers | `Level25_TimeOfDay.swift:56 (size.height>1000 && size.width>designWidth+200)` |

### L26 — LocaleScene
*ship — completability/reach verified on both layouts; 1 real polish (iPad t=0 reads as broken void), 1 cosmetic (post-solve revert never rescrambles), the rest already-fixed or false-positives*

**Top actions:**
- iPad polish: give the hidden staircase a faint low-alpha ghost outline (keep physics non-solid) so the t=0 wide-canvas frame reads as 'a route waiting to be revealed' instead of a broken empty void — the only survivor with real player-facing impact.
- Optional cosmetic: drop the language==baseline early-return and let puzzleLatched drive rescrambleTextOnly() on revert, so the atmospheric re-scramble actually fires after solving (currently a no-op).
- Optional fairness hardening: in unscrambleWorld(), gate each wrong-platform de-solidify on Bit not currently resting on it, so a solve performed while standing on the wrong cluster can't drop him (self-recovers via respawn today, so low priority).

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | Stuck-but-alive player on rest pad never gets a hint (escalation only on death) | `BaseLevelScene.swift:708-718 (no-progress wall-clock fallback)` |
| real-unfixed | cosmetic | Revert-to-baseline after solving leaves signs permanently unscrambled (early-return makes revert branch unreachable) | `Level26_Locale.swift:670-672 vs 683-691` |
| false-positive | n/a | Locale identifier en-US vs en / raw == vs lowercased() inconsistency could misclassify a change | `LocaleManager.swift:58-64; Level26_Locale.swift:670,679` |
| false-positive | n/a | Nil-baseline risk: if currentLanguageCode is nil, changedFromBaseline falls back to 'en' and could auto-solve on launch for non-English devices | `LocaleManager.swift:58-64; Level26_Locale.swift:101,670-679` |
| false-positive | n/a | Cold-boot baseline drift: changing device language while app is killed re-baselines so switching back won't solve | `Level26_Locale.swift:101,679` |
| real-unfixed | polish | iPad t=0 reads as a broken empty void — hidden staircase is alpha=0/non-solid so the vertical center is dead and the exit floats isolated top-right | `Level26_Locale.swift:385 (p.alpha = 0 on hidden stairs)` |
| false-positive | n/a | 137.5pt iPhone dead-end gap / 120pt iPad switchback span not marked off-limits — players waste lives testing the wrong route | `Level26_Locale.swift:175-180 (wrong route); buildComposedIPadLevel switchback` |
| false-positive | n/a | DEBUG test button toggles only ja/en — won't trigger a solve if baseline is neither | `Level26_Locale.swift:799-801` |
| new | fairness | Solving while standing on a wrong platform de-solidifies footing under Bit, dropping him to the death plane | `Level26_Locale.swift:719-725 (unscrambleWorld wrong-platform fadeout) / 222,428 (death zones)` |
| already-fixed | n/a | deltaTime spike on resume causing physics jump | `BaseLevelScene.swift:697-698 (clampedDt = min(dt, 1.0/30.0))` |

### L27 — VoiceOverScene
*ship — 0 crash/softlock, 1 real polish (rapid-toggle alpha overlap), 1 minor real polish (first-encounter cue), the rest false-positives or already-handled; iPad clarity is the only judgment call*

**Top actions:**
- Lower the explicit-cue threshold: surface the 'phase the path in via the bottom-left accessibility button' nudge on the FIRST death (or a ~6s idle), not death #2, to close the pre-first-death opacity window without spoiling the cryptic plaque.
- (Optional, visual) Widen the iPad zig-zag column from dx ±58 toward ±180-220 and widen REST/BREATH platforms so the climb fills the 1024+pt canvas instead of a thin centered ribbon — re-verify every consecutive edge-to-edge gap stays <=130 at the larger offsets.
- (Cheap robustness) Add removeAllActions() on real-stone surfaces at the top of dimRevealedState() to kill any in-flight reveal fade on rapid VoiceOver on/off toggles (cosmetic flicker only).

| status | sev | finding | ref |
|---|---|---|---|
| false-positive | n/a | forceHardwareFallback(.voiceOver) never cleared → leaks into later levels | `VoiceOverScene.swift:120; AccessibilityManager.swift:131-152` |
| real-unfixed | polish | First-encounter opacity: t=0 panel doesn't name the accessibility/VoiceOver fix; players may tap or hunt for a mic | `VoiceOverScene.swift:715-733 (panel), 979-994 (death>=2 nudge), 1010-1012 (hintText)` |
| real-unfixed | polish | iPad climb is a ~250pt centered zig-zag column on a 1024+pt canvas → large blank L/R margins read as underfilled | `VoiceOverScene.swift:337-352, 376-389 (dx ±58 around center)` |
| real-unfixed | polish | Rapid VoiceOver on/off can leave real-stone surfaces mid-fade (alpha overlap between showRevealedState and dimRevealedState) | `VoiceOverScene.swift:823-826 (showRevealedState removeAllActions), 861-866 (dimRevealedState sets alpha directly, no removeAllActions)` |
| false-positive | n/a | systemReduceMotion is read but never used to suppress decoy pulse | `VoiceOverScene.swift:841-855` |
| false-positive | cosmetic | setupBit() hardcodes verticalTier(0, of: 14) independently of tierCount | `VoiceOverScene.swift:745` |
| false-positive | n/a | decoyPositions comment claims decoys are 'capped to keep it fair' but no cap exists | `VoiceOverScene.swift:470-491` |
| false-positive | cosmetic | finale→exit gap mislabeled 76pt in comment when edge-to-edge is ~54pt | `VoiceOverScene.swift:412 (exit dx +58 from S10 dx -58 → c2c 116, e2e 76)` |
| false-positive | n/a | hardcoded wide-canvas threshold min(size)>=700 | `VoiceOverScene.swift:185` |
| new | polish | didEnd ground-contact delayed setGrounded(false) can un-ground Bit mid-stand during fast stone-to-stone hops | `VoiceOverScene.swift:956-961` |

### L28 — AirDropScene
*ship — 0 crash/softlock, 3 real polish (iPad goal not telegraphed, share-cancel has no on-screen feedback, single all-at-once hint); 4 false-positives (underscore collision, brute-force, force-unwrap crashes, struggle-coverage all disproven/already-fixed); 1 new cosmetic node-mismatch with no player impact*

**Top actions:**
- Add diegetic share-cancel feedback: in the completionWithItemsHandler else-branch set the terminal status to 'SHARE CANCELED — STILL ENCRYPTED' (Codex's suggestion) so a dismissed sheet reads as intentional, not broken.
- iPad only: anchor a small camera-pinned '→ TRANSMISSION / DOOR AHEAD' marker so the scrolled finale + signature mechanic are telegraphed from the empty-staircase spawn.
- Split the single hintText() into a two-stage ladder (first nudge points at the SHARE button / terminal-is-actionable; second is the existing full walkthrough) so the first-encounter fairness gap closes and the full answer stays earned.

| status | sev | finding | ref |
|---|---|---|---|
| real-unfixed | polish | iPad finale + locked door are off-screen at spawn; signature mechanic never telegraphed | `Level28_AirDrop.swift:228-302 (buildComposedIPadLevel) + setupBit:545-547` |
| real-unfixed | polish | Share-sheet cancel leaves terminal with no explanation (no keypad, no status text) | `Level28_AirDrop.swift:564-579 (completionWithItemsHandler else-branch)` |
| false-positive | n/a | Underscore delimiter collision in keyBtn_<char>_<i> name parsing | `Level28_AirDrop.swift:715 (btn.name) + 789-791 (components(separatedBy:"_"))` |
| already-fixed | n/a | Force-unwraps will crash if setup order/parsing drifts (terminalScreen!, keyboardNode!, keyNode.name!, randomElement()!) | `Level28_AirDrop.swift:120, 322-419, 629-777, 791, 899-901` |
| real-unfixed | polish | Single hintText() dumps the full step-by-step solution instead of stepped nudges | `Level28_AirDrop.swift:973-975 (hintText) + BaseLevelScene.swift:744-750 (notePlayerStruggle gating)` |
| real-unfixed | polish | Instruction panel never points at the actionable SHARE button (first-encounter fairness) | `Level28_AirDrop.swift:471-523 (showInstructionPanel) + 412-417 (shareBreathe)` |
| false-positive | n/a | Salted keypad is brute-forceable | `Level28_AirDrop.swift:629-653 (key build) + 798-816 (wrong-entry reset)` |
| already-fixed | n/a | notePlayerStruggle only fires on wrong-submit and death (insufficient hint coverage) | `Level28_AirDrop.swift:577 (share-cancel struggle) + 815, 959; BaseLevelScene.swift:714-718 (wall-clock fallback)` |
| new | cosmetic | unlockDoor passes the wrong node to clearGroundedIfStandingOn (doorContainer vs doorBlocker) | `Level28_AirDrop.swift:840-841 (clearGroundedIfStandingOn(doorContainer)) vs 453-457 (blocker body) + 942 (groundNode set)` |
| false-positive | n/a | isWideCanvas hard-codes the size threshold instead of a base helper | `Level28_AirDrop.swift:84 (isWideCanvas: size.height>1000 && size.width>designWidth)` |

### L29 — TheLieScene
*ship — 0 crash/softlock, 1 real cosmetic-but-thematic fix (hesitation inflation), 1 polish (deltaTime camera), 1 minor polish (walk-back waypoint); 4 false-positives, the DeepSeek "stranded by cancel()" and "fakeExit off-screen" scares both disproved by current code.*

**Top actions:**
- Stop counting hesitations once hasReachedFakeExit is true (one-line guard in updatePlaying ~L813) so the PLAYER ANALYSIS / TRUST readout reflects real pre-reveal behavior instead of ~2 phantom cutscene hesitations — restores the level's thematic gotcha at near-zero risk.
- Optional polish: frame-rate-normalize the updateCamera lerp (multiply/exponentiate by deltaTime) so the long traversal pans consistently on 60Hz vs 120Hz devices.
- Optional polish: drop one mid-course world-space '<<' waypoint (or briefly re-glow the real door) on the walk-back so the return trip has a confirming beat before the spawn door scrolls into view.

| status | sev | finding | ref |
|---|---|---|---|
| real-unfixed | cosmetic | hesitationCount inflates during the reveal cutscene, corrupting the TRUST readout | `Level29_TheLie.swift:813-824 (updatePlaying hesitation block); snapshot read at showPlayerAnalysis():694-735` |
| real-unfixed | cosmetic | updateCamera lerp is frame-rate dependent (no deltaTime scaling) | `Level29_TheLie.swift:775-781 (updateCamera, newX = currentX + (targetX-currentX)*0.1)` |
| real-unfixed | polish | Long walk-back from fake exit to spawn has no mid-course confirming waypoint | `Level29_TheLie.swift:633-672 (GO BACK arrow + chevron, camera-pinned); platforms only shaken not removed at 609-617` |
| false-positive | n/a | playerController.cancel() supposedly never re-enables control and strands the player | `PlayerController.swift:177-182 (cancel); 124-144 (touchBegan); BaseLevelScene.swift:720 (updatePlaying still ticks)` |
| false-positive | n/a | Camera clamp leaves the fake exit off-screen on iPad so player walks toward something invisible | `Level29_TheLie.swift:777 (targetX clamp), :54 (fakeExitX = levelWidth-50)` |
| false-positive | n/a | Lazy levelWidth/worldWidth won't update if canvas size changes after configureScene | `Level29_TheLie.swift:50 (lazy levelWidth), :528 (worldWidth); BaseLevelScene.swift:243-261 (one-shot config), :441-447 (didChangeSize no rebuild); project.yml:43-44 (portrait-only)` |
| false-positive | n/a | iPhone jump reach is punishing — 50pt gap + 30pt rise consumes most of Bit's air, spike at x=600 taxes the same window | `Level29_TheLie.swift:139-147 (phone platform data); :185-203 (hazards)` |
| false-positive | n/a | iPad vertical-tier climb collapses to a flat strip (verticalTier returns ground when size.height <= 1000) | `BaseLevelScene.swift:99-106 (verticalTier guard size.height>1000); Level29_TheLie.swift:227-332 (buildComposedIPadLevel)` |
| false-positive | n/a | Reveal reads as an ambush, not a puzzle — first-timers have no visual reason to doubt the fake exit | `Level29_TheLie.swift:105-113 (suspicious subtitle), :878-880 (hintText), :862 notePlayerStruggle escalation` |
| real-unfixed | cosmetic | Code-quality nits: hardcoded "LEVEL 29" title and unexplained 3.8s reveal duration | `Level29_TheLie.swift:95 ("LEVEL 29"), :548-553 (0.8+3.0 sequence)` |

### L30 — CreditsFinaleScene
*ship — 1 real polish fix (double victory path), 1 phone-only cosmetic (bugs float off rung edges), rest false-positives/already-fixed; no crash or softlock, reach provably safe both devices*

**Top actions:**
- Remove the duplicated victory juice: in handleExit() let succeedLevel() own the win OR strip the redundant confetti/haptic/audio/flash/slowMotion + suppress the generic 'LEVEL COMPLETE' marquee so only the bespoke 'Y O U W I N' fake-out plays (Level30_CreditsFinale.swift:937/695).
- Fix phone bug placement so hazards sit on their rungs: set bug x to the actual rung center (w/2 ∓zigzagOffset for the matching credit index) and clamp scurryRange to rungHalfWidth − bugHalfWidth (Level30_CreditsFinale.swift:492) — phone-only cosmetic, iPad placeBug already correct.

| status | sev | finding | ref |
|---|---|---|---|
| real-unfixed | polish | handleExit fires BOTH base victory effects and a bespoke victory sequence — duplicated confetti/haptic/audio + a stray 'LEVEL COMPLETE' marquee over the fake-out | `Level30_CreditsFinale.swift:937 handleExit() / 695 playVictorySequence()` |
| real-unfixed | cosmetic | Phone bugs scurry off the credit rung edges into mid-air (wrong column parity + offset magnitude + scurry range) | `Level30_CreditsFinale.swift:492 createBugs()` |
| false-positive | n/a | Fourth-wall signs absent on the iPad path | `Level30_CreditsFinale.swift:405-421` |
| false-positive | n/a | hintText() is static and ignores struggleCount — no per-death escalation | `Level30_CreditsFinale.swift:947 hintText() / BaseLevelScene.swift:765 showDifficultyHintIfNeeded()` |
| false-positive | n/a | centers.last! force-unwrap in composed iPad finale | `Level30_CreditsFinale.swift:396` |
| false-positive | n/a | createBug scurry uses hardcoded duration/range that breaks on resize/dynamic width | `Level30_CreditsFinale.swift:435 placeBug() / 521 createBug()` |
| false-positive | n/a | Completion state vs narrative position can diverge if app is killed mid victory-sequence | `Level30_CreditsFinale.swift:716 playVictorySequence() / 856 glitched_reached_credits` |
| false-positive | n/a | VoiceOver focuses bug/exit at stale screen locations (isAccessibilityElement set, no accessibilityFrame) | `Level30_CreditsFinale.swift:574-578, 610-614` |
| already-fixed | n/a | t=0 instruction-panel / title / spawn overlap (panel on finale tier & exit door on iPad; title-glyph & pause-column clip on iPhone; Bit spawning over TEACH text) | `Level30_CreditsFinale.swift:97-126 setupLevelTitle() / 618-657 showInstructionPanel() / 659-674 setupBit()` |
| false-positive | n/a | Jump reach / completability | `Level30_CreditsFinale.swift:157 verticalSpacing=76 / 304 halfSpread / 315 tierCount` |

### L31 — FlashlightScene
*ship — 0 real fixes worth doing; 1 minor polish nicety optional. 6 false-positives, 2 already-handled-by-base, geometry/completability verified clean on both form factors.*


| status | sev | finding | ref |
|---|---|---|---|
| false-positive | polish | Hint ladder is all-or-nothing / no idle nudge before full reveal | `Level31_Flashlight.swift:1714 (notePlayerStruggle) + BaseLevelScene.swift:744-750, 714-718` |
| false-positive | cosmetic | resetProgressTimer() used instead of notePlayerProgress() on flashlight-on / checkpoint | `Level31_Flashlight.swift:1584,1593,1624 + BaseLevelScene.swift:731-733` |
| false-positive | polish | Light cone stutters: currentPitch only updated on discrete .flashlightAngleChanged events | `FlashlightManager.swift:36-46 + Level31_Flashlight.swift:1643-1645` |
| false-positive | cosmetic | caveCreatures retain cycle when a creature flees | `Level31_Flashlight.swift:1255-1268` |
| false-positive | cosmetic | instructionPanel force-unwrapped at gameCamera.addChild(instructionPanel!) | `Level31_Flashlight.swift:1319-1324` |
| false-positive | cosmetic | isWideCanvas hardcoded 700pt falls back to iPhone layout in iPad Split View | `Level31_Flashlight.swift:107` |
| real-unfixed | cosmetic | tierNear strict < tie-break snaps stalactite x=2630 to the lower tier | `Level31_Flashlight.swift:516-523,533-545` |
| new | polish | iPad walk-by-one backfill can produce a 2-tier first jump at count=16 | `Level31_Flashlight.swift:497-503,125-129` |

### L32 — MultiTouchScene
*ship — 0 crash/softlock survivors; the panel's headline "stuck-alive player gets no help" is already-fixed by the base-class 22s no-progress fallback + explicit hintText; 1 polish survivor (graduated nudge), plus 1 new minor polish edge (two fingers on one pad); kimi's debug-gate-the-fallback and codex's resetProgressTimer findings are false-positives*

**Top actions:**
- (Optional, polish) Add one graduated first-nudge before the full hintText so the no-progress safety net escalates ('try holding two glowing pads at once' -> then the full instruction) instead of firing the complete spoiler in one shot. The player is never stranded today, so this is taste, not a fix.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | fairness | Stuck-but-alive player never gets escalating help (death-gated hints, no hazards in level) | `BaseLevelScene.swift:708-718 (no-progress fallback) + Level32_MultiTouch.swift:1335 hintText()` |
| real-unfixed | polish | Single exhaustive hint instead of a graduated 2-step nudge | `Level32_MultiTouch.swift:1335-1337 hintText()` |
| false-positive | n/a | Multi-touch fallback (handleGameInput .multiTouch) can open every gate without touching a plate | `Level32_MultiTouch.swift:912-943 + GameRootView.swift:295-296, 308-321` |
| false-positive | n/a | Opening a gate calls resetProgressTimer() instead of notePlayerProgress(), so hint state may not reset cleanly | `BaseLevelScene.swift:731-733; Level32_MultiTouch.swift:1037` |
| false-positive | n/a | Stuck plate left permanently active if touchesCancelled is dropped (Control Center / app-switch gesture) | `Level32_MultiTouch.swift:903-910 touchesCancelled + 1057-1063 handleGroupDeactivated` |
| false-positive | n/a | movementTouch never reassigns -> player runs out of digits for the 4-plate finale | `Level32_MultiTouch.swift:877-880 + handleGroupActivated 1034-1055 (gate latches)` |
| false-positive | n/a | isWideCanvas magic-number threshold misclassifies 11-inch iPad in landscape -> drops to phone layout | `Level32_MultiTouch.swift:78 isWideCanvas` |
| false-positive | n/a | iPad hand-composed climb is purely decorative / invites climbing toward high plates | `Level32_MultiTouch.swift:337-375 (design comment) + 453-510 climb tiers` |
| new | polish | Two fingers on the same pad -> one lifting deactivates the pad while the other still holds it | `Level32_MultiTouch.swift:868-875 (trackedTouches[touch]=index) + 897 (deactivatePlate on first end)` |
| real-unfixed | cosmetic | Plate-vs-jumpable-rung visual crowding on iPad (rungs overlap plate rings) | `Level32_MultiTouch.swift:631-636 (plate positions) + 488-510 (climb rungs)` |

### L33 — AppReviewScene
*ship — flat finale is completability-bulletproof; 0 crash/softlock, 1 real cosmetic iPad-framing void + 1 rare cosmetic double-unlock race, the rest already-fixed or false-positive (hint hook, super.touchesBegan, dead review path, fragment physics all stale/intentional)*

**Top actions:**
- Add `guard !inLevelReviewButtonUsed` to the .appReviewReturned branch in handleGameInput (Level33_AppReview.swift:1312) so the accessibility event can't re-enter unlockDoorFromOptionalReview during the ~1.15s before exitUnlocked flips — eliminates the only remaining double-shatter race (one line, cosmetic).
- iPad-only polish: lower gameplayVerticalLift's target (or extend the decorative shaft pillars below the ground line) so the bottom ~40% of the iPad canvas isn't an empty dotted void on this flat finale — visual only, iPhone unaffected.
- Optional tonal cleanup: suppress the generic 'LEVEL COMPLETE' marquee/confetti/slow-mo on L33 so the bespoke game-complete cinematic isn't preceded by a per-level completion card.

| status | sev | finding | ref |
|---|---|---|---|
| already-fixed | n/a | handleDeath does not call notePlayerStruggle / stuck player gets no escalating help | `Level33_AppReview.swift:1411 (notePlayerStruggle) + BaseLevelScene.swift:714-718` |
| false-positive | n/a | touchesBegan never calls super, silently suppressing pause-button handling | `Level33_AppReview.swift:1321-1341 vs LevelHeaderHUD.swift:176-198` |
| false-positive | n/a | No real App Store review is requested; VALIDATE ME / .appReview path is dead | `Level33_AppReview.swift:104-105, 966-968, 1309-1319 + GameRootView.swift:298-299` |
| false-positive | cosmetic | Padlock fragments have no physics body, so they fall through the floor instead of bouncing | `Level33_AppReview.swift:1106-1130` |
| false-positive | n/a | isWideCanvas bound (height>1000 && width>=820) also matches iPad landscape, contradicting the 'portrait' comment | `Level33_AppReview.swift:65 + BaseLevelScene.swift:38` |
| false-positive | n/a | 10s fallback (reviewUnlockFallback) runs even after the button is tapped → double unlock | `Level33_AppReview.swift:1023-1037, 1069-1071` |
| new | cosmetic | Residual double-unlock race: button tap then .appReviewReturned within ~1.15s both reach unlockDoorFromOptionalReview | `Level33_AppReview.swift:1311-1315 (handleGameInput) vs 1023-1037 (requestAppReview)` |
| real-unfixed | cosmetic | iPad framing leaves the entire lower ~40% of the canvas as empty dotted void below the ground line | `Level33_AppReview.swift:186-187 + drawIPadUpperBandDecor 234-280 + BaseLevelScene.swift:37-42` |
| new | cosmetic | Generic 'LEVEL COMPLETE' marquee + confetti + slow-mo fires on the true finale before the game-complete cinematic | `Level33_AppReview.swift:1195 (succeedLevel) + BaseLevelScene.swift:547-579 (playVictoryEffects)` |
