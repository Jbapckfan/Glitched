# MBP Task: iPad vertical-void pass (P1 visual polish)

> Authored by Mac Mini after a build+screenshot pass on iPad Pro 13" (1024-wide
> canvas). main @ 5a3dfcb. This is the MBP's lane (mirrors the L7-L10 geometry
> work). Mac Mini is concurrently NOT touching these scene files — coordinate via
> .agent-claims before starting.

## The problem (visual ground-truth, not static)

On iPad, "flat" single-screen levels — the ones built around a low ground line —
render with the gameplay course **horizontally centered (good, the courseX pass
worked) but bottom-anchored**, leaving the **top ~70-75% of the iPad screen as
empty dead space**. It's beatable, but it reads as broken/unfinished to a player
or an App Store reviewer.

Evidence (screenshots in build/shots/, sent to operator):
- `ipad_L33.png` — WORST: a thin strip of floor at the very bottom, ~75% empty pink above.
- `ipad_L17.png`, `ipad_L18.png`, `ipad_L32.png` — same bottom-anchored void.
- `ipad_L1.png`, `ipad_L6.png` — GOOD reference: tall geometry (pillars / vertical
  climb) fills the screen; these need NO change.

Root cause: the centered-course pass (L3 pattern) only centered the X axis;
vertical layout still keys gameplay Y off a fixed low `groundY` regardless of
canvas height. On a 932-tall iPhone that fills the screen; on a 1366-tall iPad it
floats at the bottom.

## The fix

Vertically center (or proportionally raise) the gameplay band on tall canvases so
flat levels fill the iPad screen the way L1/L6 already do — WITHOUT changing
iPhone layout or any gap/rise/jump geometry (completability must stay identical).

Recommended approach (least risk): introduce a per-scene vertical offset applied
to the gameplay container/world, computed from spare canvas height, e.g.
`courseOriginY = max(0, (size.height - designSize.height * courseScale) * centerFactor)`
with `centerFactor ~0.4` (slightly above true-center reads better than dead-center),
and add it to gameplay Y. Keep decorative/background and HUD where they are
(they already key off size/topSafeY). Mirror the horizontal courseX pattern.
Alternatively raise `groundY` proportionally on tall canvases — whichever is
cleaner per scene.

## Scope (verify each on iPad 1024 + iPhone 390 after)

Flat/bottom-anchored levels that need it (confirm by screenshot):
L17, L18, L32, L33 (confirmed bad), plus check the other raw-size.width / flat
courseX levels: L2, L7, L11-L16, L19-L26, L27, L28, L30.

EXCLUDE (already fill the screen — do NOT change):
- Tall/climb levels: L1, L6, L8, L10, L30(credits climb)
- worldWidth-camera levels: L5, L9, L29, L31 (camera handles framing)
- L0 boot scene (bespoke)

## Constraints
- Do NOT change any horizontal courseX/courseLen geometry, gaps, rises, or spawn/
  exit positions relative to the ground — completability must be byte-identical.
- Do NOT touch reserved shared files (AccessibilityManager, GameRootView, Info.plist,
  PlayerController). BaseLevelScene MAY be touched IF you add a shared
  `courseOriginY`/vertical-center helper there — but coordinate it as the shared
  pass and flag it.
- Character (Bit) is created canonically everywhere; don't touch BitCharacter.
- Build iPhone + iPad after; screenshot 4-5 fixed levels on iPad to prove the void
  is gone and iPhone is unchanged.
- Land on its own branch + PR like L7-L10; rebase on latest main first.

## Acceptance
Each in-scope level on iPad: gameplay band occupies a reasonable central portion
of the screen (no >50% empty void), iPhone visually unchanged, level still
completable on both. Attach before/after iPad screenshots to the PR.
