# Glitched — Review Console & Fix Campaign — RESUME

Snapshot saved 2026-06-26. This branch (`review-wip`) holds the 5-reviewer console artifacts
+ the review-driven code fixes, so a future session can continue.

## State of the game (on `main`)
- Native-iPad redesign + de-spoil + finale restructure → **MERGED** (PR #13, merge `ac1ac27`).
- Level reorder (demo ends on Orientation; W3 opens on Device Name) → **MERGED** (PR #14, merge `2d0c554`).
- Review-driven fixes → **PR #15 `fix/review-driven` (DRAFT, NOT merged)** — awaiting operator review.
  iPad-void confines (L2/3/4/14/16/18), L5 de-spoil, hint-net (L9/13/19/24/33), L28 crash-harden.

## The 5-reviewer console
Every level reviewed by **Claude** (visual+code), **Codex** (gpt-5.5), **Gemini** (2.5-flash, AI Studio),
**Kimi K2**, and **DeepSeek** — all read-only opinion files, no code edits.
- `reviews/claude/` … wait, Claude is in `_tooling/claude-reviews.json` (structured), others are `.md`.
- `reviews/{codex,gemini,kimi,deepseek}/<SceneClassName>.md` — first line `Level <N> — <mechanic>`.
- `reviews/iphone/L00.png` … `L33.png`, `reviews/ipad/L00.png` … — device screenshots (post-reorder).
- **Coverage: Claude/Codex/Gemini/Kimi 34/34; DeepSeek 23/34.** DeepSeek + the final Gemini pass were
  both run via the operator's own model accounts over the 23-scene bundle
  (`~/Desktop/glitched-gemini-remaining.md`), pasted back, then split with `_tooling/parse_reviews.py
  <response.txt> <tool>`. DeepSeek is missing the FIRST 11 scenes (L0,1,2,3,4,6,9,11,12,13,14 — not in
  that bundle); re-bundle those + paste-back to reach 34/34. (Old agentic Gemini CLI path is dead:
  free Code Assist tier deprecated → `IneligibleTierError`.)

## Rebuild the console (5-column HTML: iPhone | iPad | Claude | Codex | Gemini | Kimi | DeepSeek)
`python3 reviews/_tooling/build_console.py` → writes a self-contained `glitched-console.html`.
NOTE: the `_tooling/*.py` and `*.js` have HARDCODED scratchpad paths from the original session —
fix the `CL`/`SCRATCH`/`S` constants to the new clone path before re-running.

## How the level number ↔ scene file map works (post-reorder!)
Level number = `levelID` inside each scene's `configureScene`, NOT the filename:
- Level 9 = `Level10_TimeTravel.swift` (TimeTravelScene); Level 10 = `Level9_Orientation.swift`.
- Level 21 = `Level23_DeviceName.swift`; Level 22 = `Level21_VoiceCommand.swift`; Level 23 = `Level22_BatteryPercent.swift`.
- `_tooling/build_console.py` has the full CLASS_TO_LEVEL map.

## Walkthrough backlog (subjective — decide WITH the operator)
- Marginal iPad framing on flat levels **L11, L17, L25** (bottom-heavy; not confine candidates).
- Per-level polish from the reviews: redundant panels, difficulty tuning, voice consistency,
  the **narrative-arc lens findings** (in the narrative-workflow output), t=0 text-over-sprite
  nits (L1/L5/L6 whisper placement).
- Finish the Gemini column (quota reset).
- The operator was doing a **live two-sim walkthrough** (iPhone 17 + iPad Pro 13") — `GLITCHED_START_LEVEL`
  jump hook; re-boot both sims + launch the build to resume.

## Tooling index (`reviews/_tooling/`)
- `build_console.py` — generate the HTML console.
- `gemini_review.py` — paced 1-call-per-scene Gemini review (curl).
- `claude-reviews.json` — Claude's 34 structured reviews (verdict/score/strengths/concerns/clueHint/suggestion).
- `*-prompt.txt` — the shared review prompt given to each CLI reviewer.
- `*-workflow.js` — the audit/apply Workflow scripts used this session (audit, narrative, despoil, apply-stage*, apply-w*).
