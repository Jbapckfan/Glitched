# Glitched — Full Design & QA Review (34 levels)

> Review date: 2026-05-31. Read-only audit of all level scenes + shared systems.
> Method: 7 parallel deep-readers (5 levels each) + manual verification of the
> two highest-stakes claims (orientation lock, accessibility-fallback gating).
> No gameplay code was changed to produce this document.
>
> Citations are `file:line` against the tree at the time of review; line numbers
> drift as the code changes — grep the cited symbol if a line looks off.

---

## Root cause behind most completability bugs

A device-mechanic level is playable on the Simulator / in accessibility mode
**only if it calls `AccessibilityManager.forceHardwareFallback(for:)`** — that's
what makes the on-screen fallback button appear. The gating logic is in
`Glitched/Core/AccessibilityManager.swift:78-85`:

```swift
func usesHardware(for mechanic: MechanicType) -> Bool {
    if hardwareFreeMode { return false }
    return !forcedFallbacks.contains(mechanic)   // false unless forced
}
func needsFallbackUI(for mechanic: MechanicType) -> Bool {
    guard activeMechanics.contains(mechanic) else { return false }
    return !usesHardware(for: mechanic)          // -> no button unless forced/HFM
}
```

Only **World 1's L1, L2, L4** (+ the motion manager) call `forceHardwareFallback`
under `#if targetEnvironment(simulator)`. Every other hardware level is, by
default, **not completable on the Simulator** unless the player manually enables
Hardware-Free Mode in Settings — and several fallback buttons are missing
entirely or post the wrong value even then.

**Systemic fix (clears ~10 findings at once):**
1. Audit every level's `configureScene` for a `#if targetEnvironment(simulator)`
   `forceHardwareFallback` call matching its mechanic.
2. Make every fallback event posted by `GameRootView.AccessibilityOverlay`
   actually drive that level's win (some are dead — no `handleGameInput`
   consumer), and express BOTH states for "keep-it-low/keep-it-off" mechanics.

---

## Completability bugs, severity-ranked

### P0 — hard unwinnable / softlock

1. **L9 Orientation — unwinnable as designed.** `Glitched/Info.plist`
   `UISupportedInterfaceOrientations` = `UIInterfaceOrientationPortrait` only, so
   "rotate to landscape" can never satisfy the UI; only the accessibility button
   (single `isLandscape:true` pulse) solves it, defeating the premise.
   *Fix:* allow landscape + handle SpriteKit resize, or rebuild the mechanic, or
   pull the level until landscape is supported.

2. **L13 WiFi — contradictory rule kills the player.** Stepping stones require
   WiFi **ON**; the wall on the same path requires WiFi **OFF**. Toggling off to
   pass the wall removes the platforms under Bit → fall to death zone. No
   sequence satisfies both. `Level13_WiFi.swift:354-373`, `86-90`.
   *Fix:* put the WiFi platforms and the WiFi wall on disjoint segments, or add
   coyote-grace so toggling off doesn't instantly drop a standing player.

3. **L23 Device Name — exit never unlocks, no fallback.** Exit blocker only
   clears via the doppelganger script gated entirely on `.deviceNameRead`
   (`Level23_DeviceName.swift:339-340,411-416,450`). There is **no `.deviceName`
   fallback button** in `GameRootView`, and Hardware-Free Mode *deactivates* the
   manager (`DeviceManagerCoordinator.swift:100-108`), so the event never fires →
   permanently locked exit while the decoy name-door stands open.

4. **L32 Multi-Touch — sim-impossible + dead fallback.** Needs 3–4 simultaneous
   touches (`Level32_MultiTouch.swift:85,233,268`); the Simulator caps at 2. The
   `.multiTouch` fallback event (`GameRootView.swift:243`) has **no consumer** —
   `MultiTouchScene` has no `handleGameInput` — so even Hardware-Free Mode can't
   solve it. Also cramped/impossible on small iPhones (4 fingers in the right 20%).

5. **L15 Low Power — sim-impossible, one-way fallback.** Can't enable Low Power
   Mode in the Simulator; the `.lowPowerMode` fallback posts only `isEnabled:true`
   with no "off" button, and the level needs LPM **off** (section 2) then **on**
   (section 3) with no in-level toggle → directional softlock.
   `Level15_LowPower.swift:99-121`. *Fix:* add an in-level toggle like L14's DND
   button.

6. **L21 Voice Command — fallback can't speak the needed words.** The
   `.voiceCommand` fallback posts only `command:"open"` (`GameRootView.swift:216-218`);
   "BRIDGE" and "FLY" are both required (`Level21_VoiceCommand.swift:460-465`) and
   unreachable; `voiceCommandMicDenied` is posted by the manager but never handled
   in the scene → unwinnable with no mic / in sim / hardware-free.

7. **L10 Time Travel — no fallback at all.** `GameRootView.AccessibilityOverlay`
   has **no `.appBackgrounding` button**; the only alternate event
   (`.timePassageSimulated`) is never posted by the shipped overlay → hardware-free
   players cannot advance the tree. *Fix:* add an `.appBackgrounding` fallback
   button.

### P1 — situational unwinnable / strong risk

8. **L31 Flashlight** — no `#if simulator` fallback (`Level31_Flashlight.swift:77`);
   on sim torch+motion are dead so no button appears and hazards stay invisible.
   Even when forced, the single frozen `pitch:-1.2` pulse
   (`GameRootView.swift:239-240`) lights ceiling stalactites but never the
   flat-pitch floor-pit sections (`Level31:303,1104-1111`) → only half-solvable.

9. **L28 AirDrop** — the unlock keypad appears only on share-sheet
   `completed==true` (`Level28_AirDrop.swift:308-313`). Cancel the sheet (or run on
   a Simulator with no share targets) → door stays locked permanently. No
   `#if DEBUG` test button (unlike L26/L27). *Fix:* simulator force-fallback
   and/or a same-device path that doesn't require share *completion*.

10. **L27 VoiceOver — user-trap.** Enabling VoiceOver (the level's literal
    instruction, `Level27_VoiceOver.swift:253,471`) makes it intercept all touches
    → Bit can't be controlled; the scene never handles VoiceOver-routed input.
    Only the after-3-deaths hint fallback (`:310-348,:454`) keeps it winnable, and
    only if VoiceOver stays OFF. *Fix:* make the death-hint fallback the primary
    path and VoiceOver a flavor easter egg.

11. **L11 Notification** — the tappable faux-notification only fires when auth is
    explicitly `.denied` (`Level11_Notification.swift:445`); provisional/undetermined
    sim runs get no tappable target. The shared 3-request auto-unlock counter can
    be spent on door 0, stranding door 1 (`:404-405`). *Fix:* show the faux
    notification after a short timeout regardless of permission state.

12. **L4 Volume — invisible escalating threshold = hidden time limit.**
    `safeZoneShrinkFactor` drops the wake threshold to ~0.20 over ~24s with no
    on-screen cue (`Level4_Volume.swift:854-861`); any device resting above ~20%
    volume eventually wakes the wolf with no counter. *Fix:* remove the shrink,
    expose it visually, or floor it above realistic resting volume. Also: the
    water-drown system is redundant with the wolf — consider cutting it.

13. **L18 App Switcher — mechanic mis-wired.** Registers `.appSwitcher`
    (`Level18_AppSwitcher.swift:36`) but its solve path listens for
    `.appBackgrounded` (a different manager that's never activated, `:388-391`);
    only beatable because the platforming is independently solvable. No
    `.appSwitcher` fallback button exists.

14. **L3 Static / L5 Charging — missing `#if simulator` fallback** (unlike L2/L4).
    On sim the mic/charging input is dead and no button appears. L3's gameplay was
    hardened with per-frame noise decay (`Level3_Static.swift:~742`), but the
    *fallback button* still won't appear on a default sim run; L5 has no decay
    equivalent and no unplug affordance.

### Correctness / smaller issues

- **L4** `updateWaterLevel` references `bit` before `setupBit()` runs — latent
  nil force-unwrap if water is ever active at init (`Level4_Volume.swift:225` vs
  configure order).
- **L16** shake threshold (10-sample avg > 2.5g, `ShakeUndoManager.swift:65-67`)
  effectively never fires on a real shake; `performUndo` wipes the whole history
  so a second undo teleports to spawn instead of rewinding 3s. Undo is optional,
  so not a softlock, but the signature mechanic is decorative.
- **L12** clipboard fallback posts `"GLITCH"` ≠ required `GLITCH3D`
  (`GameRootView.swift:194` vs `Level12_Clipboard.swift:21`) — broken for
  hardware-free players (primary copy/paste path still works).
- **L22** `updateBatteryVisuals` rebuilds particle atmosphere on every battery
  update (`Level22_BatteryPercent.swift:345-370`) — node churn under polling.
- **L33** `clearLargeTerminal` defined but never called; fixed-size 280pt
  terminals clip on SE/iPad.

### The one safe meta-level

**L20 "delete the app" is fully simulated** — `ReinstallManager.startDeletionPhase()`
is never called anywhere; nothing deletes user data or wedges the app. The purge
is a proximity-triggered fake-crash overlay. Good. (Minor: the completion flag is
in the Keychain, which survives a real reinstall, so a reinstalled app would
auto-skip the gate.)

---

## Levels that are clean / exemplary

- **L1 Header** — perfect opener; drag-the-UI gag, robust fallback, completable
  everywhere.
- **L7 Screenshot** — cleanest "aha"; `userDidTakeScreenshot` **fires on the
  Simulator** (Cmd+S), so it's natively completable without accessibility mode.
- **L12 Clipboard** — most reliable mechanic; auto-scans clipboard on load.
- **L14 Focus Mode** — only World-2 level with a real in-scene fallback button
  (DND toggle); clear instructions; genuine "disable your protection to exit"
  twist.
- **L20 Meta Finale** — great fourth-wall payoff, fully safe.
- **L29 The Lie** — best concept; correct camera-follow/worldWidth; no hardware
  dependency, no softlock.
- **L33 App Review** — finale done right: 10s auto-unlock timer means the door
  always opens whether or not the player reviews; never traps the player.

---

## Ordering analysis

World *themes* are well-sequenced (Hardware → Control → Data → Reality →
Override). The problems are **inside World 1**, the make-or-break first hour:

- **Difficulty spikes too early.** L3 (inverse mic + unsignposted 4th laser),
  L4 (3 overlapping systems + hidden timer), and the **L9 orientation wall** all
  land in the tutorial world — a new player hits an unsignposted reversal, a
  hidden time-limit, and an unwinnable-on-their-setup level before leaving W1.
- **Best onboarding mechanics are buried.** L7 (cleanest aha, works on sim
  natively) sits at 1-7; L12 (most reliable) is deep in World 2.
- **Proposed World 1 reorder:** L1 → L2 → **L7 Screenshot** → L4 Volume *(water
  cut)* → L3 Static → L6 Brightness → L5 Charging → L8 → L10 → **pull L9
  Orientation** until landscape is supported.
- **Pacing rhythm:** alternate "leave-the-app hardware effort" levels with
  "in-app cleverness" levels. World 2 currently strings four leave-the-app levels
  in a row (notification → clipboard → wifi → focus → lowpower).
- **World 5 is thin (3 levels) and ends on the two weakest-fallback mechanics**
  (flashlight, multi-touch). Consider promoting a robust level into W5 so the
  closing run isn't gated on the most fragile inputs.

---

## New level ideas (reliable mechanics the roster is short on)

Criteria: works on device **and** sim, expresses both states, no Settings trip,
ideally continuous (no single-pulse problem).

1. **Gyroscope tilt-maze** — roll Bit by physically tilting (CoreMotion
   attitude). Continuous, clean on-screen joystick fallback. The "marble" level
   the genre is missing.
2. **Proximity/cover-the-sensor "blink"** — cover the top sensor to freeze a
   light-fearing enemy (SCP-173 style). `ProximityManager` already exists.
3. **Battery-as-resource (not gate)** — a torch/shield meter mirroring real
   battery %; low battery = dimmer light. Ambient pressure instead of L22's
   impractical "drain 40%."
4. **Silent-mode/ringer switch** — flip the hardware mute switch to silence an
   alarm that summons enemies. A physical binary toggle, untouched.
5. **Type-the-glitch** — keyboard rises; type what the corrupted sign *should*
   say. Pure in-app, sim-safe, fits "data corruption."
6. **Pinch-to-zoom reality** — pinch to reveal platforms visible only at a
   certain zoom. Native gesture, continuous.
7. **Two-finger rotate a cog** — twist to align a path. Multi-touch *without*
   L32's 4-finger impossibility.
8. **Long-press "hold the door"** — press-and-hold a plate while a second finger
   walks Bit through. Gentle multi-touch primer before L32.
9. **Screen-record meta** — detect `isCaptured` to "watch yourself"; a World-4
   reality-break beat.
10. **Shake-to-scramble done right** — shake to reroll a randomized layout until
    solvable; makes shake required + frequent with a fixed threshold + button
    fallback (fixes L16's decorative shake).

**Cut/rework candidates:** L9 (until landscape), L27 VoiceOver-as-primary
(make death-hint primary), L4's water system (redundant), L22's
"really drain your battery."

---

## Suggested fix order

1. **Systemic:** add `#if targetEnvironment(simulator) forceHardwareFallback`
   to every hardware level; wire every `AccessibilityOverlay` fallback event to a
   `handleGameInput` consumer and add the missing buttons (`.deviceName`,
   `.appBackgrounding`, `.appSwitcher`); make low/off-state mechanics two-way.
   → clears L3, L5, L10, L21, L23, L31, L32 fallbacks at once.
2. **L13 WiFi** redesign (disjoint segments).
3. **L9 Orientation** decision (landscape support vs pull).
4. **L4** remove/expose the shrink timer; consider cutting water.
5. **L27** make death-hint the primary path.
6. Correctness cleanup (L4 ordering, L16 shake, L12 fallback string, L22 churn).
