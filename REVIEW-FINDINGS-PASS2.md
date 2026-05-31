# Glitched — Deep Second-Pass Review (L13–L33)

> Review date: 2026-05-31. Read-only. Method: 5 principal-level parallel
> reviewers, each doing line-level correctness + exploit hunting + adversarial
> re-verification of pass-1 findings. Complements `REVIEW-FINDINGS.md` (pass 1).
> No gameplay code changed to produce this doc. Line numbers drift — grep the
> cited symbol if one looks off.

---

## NEW game-ending softlocks pass-1 missed (highest priority)

### L20 Meta Finale — SOFTLOCK (pass-1 called this "safe / no completability bug")
The simulated-purge trigger requires `corruptionProximity > 0.9`
(`Level20_MetaFinale.swift:685`), but the corruption blocker (70×200 at x195–265,
`:295-300`) physically stops Bit at center x≈184 → closest proximity ≈ **0.77**.
**0.9 is unreachable**, so the purge never fires, the wall never clears, the exit
is permanently walled. The other clear paths are dead too (`.appReinstallDetected`
never fires; keychain flag nil on fresh install). **Fresh-install softlock.**
*Fix:* trigger `beginSimulatedPurge()` on physics contact with the blocker, or
lower the threshold to ~0.6 and verify reachability.
(Safety confirmed separately: nothing destructive — `ReinstallManager.startDeletionPhase()`
has zero callers; the "delete the app" theme is fully simulated.)

### L30 Credits Finale — SOFTLOCK (pass-1 flagged "verify jump reach")
Vertical climb with `verticalSpacing = 120` (`Level30_CreditsFinale.swift:105`),
but Bit's peak body rise is ≈ **91pt** (`jumpImpulse=470`, cap 620, gravity −14;
v²/2g ≈ 620²/4200). The **first jump already falls ~29pt short** — no double-jump,
no `clampVelocity` in this scene. The entire finale climb is impossible.
*Fix:* set `verticalSpacing ≤ 80`. Also: the death zone is pinned to the camera
(`:359-366`) so a stalled player can re-die on respawn — ease the camera back to
spawn on death.

---

## Pass-1 verifications (confirm / refute)

- **L13 WiFi fix — CONFIRMED GOOD.** The refactor (disjoint segments: stones
  crossed WiFi-ON, solid landing floor, wall passed WiFi-OFF) removes the
  contradictory-rule softlock; toggling off no longer drops Bit. One residual: the
  wall-skip jump margin is ~0.5pt and untested on iPad's 1.25× Bit scale — raise
  the wall ~15–20pt for safety.
- **L28 AirDrop "permanent lock on cancel" — REFUTED.** The SHARE button is
  re-tappable (only removed inside `showKeyboard` after success, `:320`), and the
  share sheet returns `completed==true` for Copy/Reminders on sim. NOT a lock.
  *But new:* the `.airdrop` accessibility fallback posts `code:"GLITCH"`
  (`GameRootView.swift:234`) which can never equal the random `doorCode`
  (`Level28:55-58,521-523`) → dead unlock path for hardware-free players.
- **L23 DeviceName P0 softlock — CONFIRMED in full.** Exit clears only via the
  `.deviceNameRead` → doppelganger → unlock chain; no `.deviceName` fallback
  button; hardwareFreeMode deactivates the manager → permanently locked exit with
  the decoy door open. (Completable on a real device, not in sim/hardware-free.)
- **L21 VoiceCommand P0 — CONFIRMED.** Fallback posts only `"open"`; BRIDGE/FLY
  unreachable; `.voiceCommandMicDenied` never handled.
- **L15 LowPower P0 — CONFIRMED + refined.** No in-level toggle; fallback button
  hidden AND one-way. Also the "section 2 needs normal gravity" gate is largely
  illusory (you can just walk off the ledge), so the real gate is section 3, which
  is sim-impossible.
- **L17 Airplane — CONFIRMED completable** (single ON pulse suffices; tightest jump
  is f3→landing ≈62.5pt rise/65pt gap, within arc).
- **L18 AppSwitcher mis-wiring — CONFIRMED + refined.** Peek freeze does work
  (enter + timed auto-exit), but the intended return-to-resume is dead (`.appBackgrounded`
  branch unreachable, `:397-399`); no `.appSwitcher` fallback button. Beatable only
  because platforming is independently solvable.
- **L19 FaceID — CONFIRMED + NEW sequence-break.** No `.faceID` button (proximity
  saves it); "APPROACH NEXT GATE" copy mismatches the tap requirement. **NEW:** the
  exit body (x310–350) is reachable past the still-closed door2 blocker (x335) →
  steps 2 & 3 are skippable; the whole "face changed / rescan" beat is bypassable.
- **L22 BatteryPercent — CONFIRMED.** Always-on SIM DRAIN button saves it; real
  40%-drain path is impractical; `updateBatteryVisuals` rebuilds 22 atmosphere nodes
  + full-screen overlay every battery tick (`:345-375`); `self.speed=speedFactor`
  (`:374`) slows ALL gameplay at low battery.
- **L24 StorageSpace — CONFIRMED dual path + NEW possible sequence-break.** Clean
  completability; writes a real 5MB cache file (orphaned on early quit). **NEW:** the
  data-mass wall top (y≈220) may be jumpable (apex body-bottom ≈247 from the middle
  platform) → cache mechanic skippable; verify on-device / raise the wall.
- **L25 TimeOfDay — CONFIRMED not time-lockable** (always-on CYCLE button; day mode
  beatable). Override is one-way; patrol-restart amplitude is fragile (`:374-377`).
- **L26 Locale — CONFIRMED completable + NEW.** Resume path works; DEBUG test button
  exists. **NEW:** reverting locale mid-climb (`rescrambleWorld`, `:380-400`) can
  desolidify the platform under Bit / re-solidify wrong ones → eject/strand (not
  permanent, respawns).
- **L27 VoiceOver USER-TRAP — CONFIRMED.** No `allowsDirectInteraction` (grep clean)
  and `isAccessibilityElement=true` (`:154`): enabling VoiceOver (the literal
  instruction, `:253`) routes all touches through the VO cursor → Bit can't move.
  Only the 3-death hint fallback saves it, and only if VO stays OFF. Also
  `accessibilityFrame` uses scene coords as screen coords (`:156-161`).
- **L29 TheLie — CONFIRMED clean + NEW iPad spoiler.** Camera math correct for
  worldWidth=1200. **NEW:** on width ≥ ~800 (all iPads) `levelWidth - size.width/2 <
  size.width/2`, so the camera never scrolls and the whole level (both doors) is
  visible at once → the twist is spoiled. Scale `levelWidth = max(1200, size.width*2.2)`.
- **L31 Flashlight — CONFIRMED sim-blocked + NEW: signature mechanic is inert.**
  No sim fallback. **NEW:** `gapFromFloor` is dropped (`:591-658` ignores it), so
  every stalactite hangs at `topSafeY-15`, ~340px above Bit — **no ceiling hazard
  ever threatens the player.** Floor pits are real but beatable by the always-on
  ambient/exit glow, so the flashlight is never actually required → degrades to
  "walk right in the dark."
- **L32 MultiTouch P0 — CONFIRMED + worse.** Sim caps at 2 touches; the `.multiTouch`
  fallback has NO `handleGameInput` consumer → hardware-free mode also can't solve;
  4 plates packed in the right ~20% are barely reachable on a phone.
- **L33 AppReview FINALE — CONFIRMED done right.** 10s `unlockWithoutReview` timer
  guarantees the door opens regardless of input; real review never required; never
  traps the player. Only blemish: `clearLargeTerminal` defined but never called
  (`:852`) → monologue clips on SE/iPad.
- **L14 FocusMode — CONFIRMED clean + NEW poll/manual conflict.** In-scene DND button
  works. **NEW:** `FocusModeManager`'s 0.5s poll (`:23`) mutates the same
  `lastFocusState` the manual toggle uses, so within 0.5s the poll can override a
  manual toggle and un-freeze hazards mid-traversal. Suspend the poll on manual use.
- **L16 ShakeUndo — CONFIRMED worse than pass-1.** At 60fps the 90-entry history is
  only ~1.5s, so the `gameTime-3.0` lookup never matches → **even the first undo
  teleports to spawn.** Shake threshold (10-sample avg > 2.5g) practically never
  fires; platform rewind is overwritten by its own oscillator next frame. Undo is
  optional so the level is still beatable.

---

## Consolidated severity ranking (this pass)

**P0 — completability-blocking:**
1. L20 purge trigger unreachable → exit permanently walled (`:685`).
2. L30 120pt jump gap impossible → finale climb unbeatable (`:105`).
3. L23 deviceName exit never unlocks in sim/hardware-free (no fallback + manager deactivated).
4. L21 voice fallback can't speak BRIDGE/FLY → unwinnable without a real mic.
5. L15 lowpower no in-level toggle + hidden one-way fallback → sim-blocked/directional softlock.
6. L32 multitouch sim-impossible + dead `.multiTouch` fallback consumer.
7. L31 flashlight sim-blocked (no fallback) + signature mechanic inert (`gapFromFloor` dropped).

**P1 — sequence-break / unfair / accessibility-dead:**
8. L19 exit reachable past closed door2 → scans 2–3 skippable.
9. L24 data-mass wall likely jumpable → cache mechanic skippable.
10. L27 VoiceOver user-trap (enabling the feature disables control).
11. L28 `.airdrop` fallback posts wrong code → dead unlock for hardware-free.
12. L16 undo teleports to spawn at 60fps (core mechanic broken).
13. L14 focus poll overrides manual toggle → mid-traversal un-freeze death.
14. L29 twist spoiled on iPad (camera never scrolls).

**P2 — perf / polish / fragility:**
15. L22 atmosphere rebuilt every battery tick + `scene.speed` slows gameplay.
16. L33 finale monologue clips (dead `clearLargeTerminal`).
17. L26 locale-revert mid-climb can strand the player.
18. L25 patrol-restart amplitude fragility.
19. L31 checkpoint respawn at fixed y over variable terrain; unconditional unground.
20. Cross-cutting: most levels hardcode a 390pt canvas; iPad/SE layouts unverified.

**Systemic root cause (unchanged from pass-1):** most P0s are the missing
`forceHardwareFallback` + missing/wrong `GameRootView` fallback buttons +
fallback events with no `handleGameInput` consumer. This is one serialized pass
that touches `GameRootView.swift` + `AccessibilityManager.swift` + many
`configureScene` blocks — must be done by ONE agent, after the per-level work.
