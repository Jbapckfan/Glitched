export const meta = {
  name: 'glitched-ipad-audit',
  description: 'Audit native-iPad redesign of all 34 Glitched levels (crash/void/overlap/completability) from iPhone+iPad screenshots + source; adversarially refute every blocker',
  phases: [
    { title: 'Audit', detail: '34 agents: one per level, reads iPhone+iPad shot + source + spec' },
    { title: 'Verify', detail: 'adversarial refutation of each flagged blocker' },
  ],
}

const BASE = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad'
const SHOTS = `${BASE}/shots`
const SRC = `${BASE}/glitched-redesign/Glitched/Scenes`

// kind: 'text' = full-screen text (no platform course; void N/A),
//       'camera' = scrolling/vertical course extends beyond one frame (don't flag off-screen as void),
//       'course' = single-screen course (the whole thing should be visible & fill iPad height).
const LEVELS = [
  { idx: 0,  file: 'Level0_BootSequence.swift', title: 'Boot',          kind: 'text',   guide: 'BIOS boot text scrolls, loading bar stuck at 99%; drag the circular handle right to 100%, fake crash, then transition to L1. Full-screen terminal text, not a platform course.' },
  { idx: 1,  file: 'Level1_Header.swift',       title: 'Header',        kind: 'course', guide: 'Drag the dark "LEVEL 1" banner down onto the spike pit to form a bridge; cross to the exit door on the right.' },
  { idx: 2,  file: 'Level2_Wind.swift',         title: 'Wind',          kind: 'course', guide: 'Blow into mic to extend a bridge across a chasm between two platforms; cross to exit.' },
  { idx: 3,  file: 'Level3_Static.swift',       title: 'Static',        kind: 'course', guide: 'Laser gauntlet: noise disables lasers 1-3; the 4th is inverse (noise activates it). Cross platforms to exit on the right.' },
  { idx: 4,  file: 'Level4_Volume.swift',       title: 'Volume',        kind: 'course', guide: 'Keep volume low to keep a sleeping wolf asleep and water low; navigate past the wolf to exit right.' },
  { idx: 5,  file: 'Level5_Charging.swift',     title: 'Charging',      kind: 'camera', guide: 'Vertical shaft: ride a rising charging plug UP through the shaft to the exit near the top. Course is tall (extends above the frame).' },
  { idx: 6,  file: 'Level6_Brightness.swift',   title: 'Brightness',    kind: 'course', guide: 'Raise screen brightness to fade in invisible UV platforms; avoid burn zones at max; cross to exit.' },
  { idx: 7,  file: 'Level7_Screenshot.swift',   title: 'Screenshot',    kind: 'camera', guide: 'Freeze a flickering 7-segment ghost bridge by taking a screenshot, then cross before the freeze timer expires. May extend horizontally.' },
  { idx: 8,  file: 'Level8_DarkMode.swift',     title: 'Dark Mode',     kind: 'course', guide: 'Toggle dark/light mode: moon platforms solid in dark, sun platforms solid in light; alternate to climb; exit needs dark mode. TRAP-sensitive: never widen gaps.' },
  { idx: 9,  file: 'Level9_Orientation.swift',  title: 'Orientation',   kind: 'camera', guide: 'Rotate to landscape to widen an 18pt corridor to 100pt and squeeze past an advancing crusher wall to the exit. World stretches with orientation. TRAP-sensitive.' },
  { idx: 10, file: 'Level10_TimeTravel.swift',  title: 'Time Travel',   kind: 'course', guide: 'Background the app ~5s to grow a sapling into a mature tree that forms a bridge; cross to exit.' },
  { idx: 11, file: 'Level11_Notification.swift',title: 'Notification',  kind: 'course', guide: 'Tap the bell to request push notifications; tap them to unlock two doors, then reach the exit.' },
  { idx: 12, file: 'Level12_Clipboard.swift',   title: 'Clipboard',     kind: 'course', guide: 'Copy GLITCH3D to clipboard; the terminal scans it and opens the locked door. TRAP-sensitive.' },
  { idx: 13, file: 'Level13_WiFi.swift',        title: 'WiFi',          kind: 'course', guide: 'Toggle WiFi: signal platforms solidify, signal walls block; complete a download with WiFi on; reach exit. TRAP-sensitive.' },
  { idx: 14, file: 'Level14_FocusMode.swift',   title: 'Focus Mode',    kind: 'course', guide: 'Enable Focus/DND to freeze orbiting spike hazards; navigate the frozen field to the exit (unlocks after Focus active).' },
  { idx: 15, file: 'Level15_LowPower.swift',    title: 'Low Power',     kind: 'course', guide: 'Toggle Low Power to swap gravity (normal -20 / lunar -6) across 4 sections (narrow drop needs normal; wide chasm needs lunar). TRAP-sensitive (jump tuning).' },
  { idx: 16, file: 'Level16_ShakeUndo.swift',   title: 'Shake Undo',    kind: 'course', guide: '3 shake-undo charges rewind 3s of you + a moving platform; time jumps with the moving platform to cross.' },
  { idx: 17, file: 'Level17_AirplaneMode.swift',title: 'Airplane Mode', kind: 'course', guide: 'Enable Airplane Mode to raise 3 platforms to flying positions; jump up to the high exit (groundY+200).' },
  { idx: 18, file: 'Level18_AppSwitcher.swift', title: 'App Switcher',  kind: 'course', guide: 'Peek the app switcher to freeze spikes and reveal trajectory lines; navigate gaps to exit. (POC reference level.)' },
  { idx: 19, file: 'Level19_FaceID.swift',      title: 'Face ID',       kind: 'course', guide: 'Authenticate (Face ID) to open vault door 1, then a second biometric door; reach exit.' },
  { idx: 20, file: 'Level20_MetaFinale.swift',  title: 'Meta Finale',   kind: 'course', guide: 'Walk into a pulsing corruption wall to trigger a simulated purge/reboot that clears it; reach exit. Dark, dramatic mood.' },
  { idx: 21, file: 'Level21_VoiceCommand.swift',title: 'Voice Command', kind: 'course', guide: 'Speak BRIDGE (extend bridge), OPEN/UNLOCK (open door), FLY/JUMP (upward boost to a high platform) for 3 obstacles. TRAP-sensitive.' },
  { idx: 22, file: 'Level22_BatteryPercent.swift',title:'Battery %',    kind: 'course', guide: '10 stepping stones; a FAKE exit far right at 100%. The REAL exit is hidden BELOW stone #5, revealed when battery<60% (stones 6-10 vanish). Drain button present.' },
  { idx: 23, file: 'Level23_DeviceName.swift',  title: 'Device Name',   kind: 'course', guide: 'A name-door shows your device name and opens for you; a doppelganger NPC patrols; reach the exit while the doppelganger is elsewhere. TRAP-sensitive.' },
  { idx: 24, file: 'Level24_StorageSpace.swift',title: 'Storage',       kind: 'course', guide: 'Clear app cache (or in-game CLEAR CACHE button) to dissolve a "DATA MASS" wall; reach exit.' },
  { idx: 25, file: 'Level25_TimeOfDay.swift',   title: 'Time of Day',   kind: 'course', guide: 'Night = enemies sleep (safe). Use day/night toggle; walk past sleeping enemies to exit. Secret 3:33 variant.' },
  { idx: 26, file: 'Level26_Locale.swift',      title: 'Locale',        kind: 'course', guide: 'Change device language to unscramble direction signs and swap wrong-route platforms for the correct route; follow it to exit.' },
  { idx: 27, file: 'Level27_VoiceOver.swift',   title: 'VoiceOver',     kind: 'course', guide: 'Five invisible bridge platforms (always physically solid) span a gap; VoiceOver reveals labels/shimmer; cross to exit.' },
  { idx: 28, file: 'Level28_AirDrop.swift',     title: 'Share Code',    kind: 'course', guide: 'Share a 6-char code via share sheet, then type it back on an in-game keyboard to open the door; reach exit. TRAP-sensitive.' },
  { idx: 29, file: 'Level29_TheLie.swift',      title: 'The Lie',       kind: 'camera', guide: 'Long scrolling course to a FAKE exit on the right; touching it reveals the REAL exit was behind you at spawn. Walk back left. Horizontal camera-follow (wide world).' },
  { idx: 30, file: 'Level30_CreditsFinale.swift',title: 'Credits',      kind: 'camera', guide: 'Climb credit-line platforms in a vertical zigzag (dark/inverted) to "THANK YOU FOR PLAYING"; avoid bug enemies. Vertical scroll.' },
  { idx: 31, file: 'Level31_Flashlight.swift',  title: 'Flashlight',    kind: 'camera', guide: 'Dark cave revealed by the real flashlight + phone tilt aiming a light cone; navigate ceiling hazards and pits to exit. Scrolling cave.' },
  { idx: 32, file: 'Level32_MultiTouch.swift',  title: 'Multi-Touch',   kind: 'course', guide: 'Hold circular pressure plates simultaneously (2 then 3+ fingers) to open gates while inching Bit forward; reach exit.' },
  { idx: 33, file: 'Level33_AppReview.swift',   title: 'App Review',    kind: 'course', guide: 'Clear two comedy gates; a review-prompt padlock auto-shatters after 10s; enter the final exit. Finale joke.' },
]

const RULES = `
NATIVE-iPAD REDESIGN — what "correct" means:
- iPhone layout must be UNCHANGED from before (phone is the baseline). iPad (portrait, ~1024-1366pt tall canvas) must FILL the height with MORE content at the SAME absolute spacing — never scale geometry.
- Bit's jump reach is device-INDEPENDENT and FIXED: safe edge-to-edge gap <= 130 (hard max 145), safe top-to-top rise <= 85 (hard max ~91, apex ~91pt). Widening any gap/rise past these makes a level UNCOMPLETABLE.
- A correct iPad layout raises the floor (playableGroundY) and builds UPWARD through tiers (verticalTier/fillTierCount) and/or wider courses, and installs installCameraFollow(worldWidth:) when the course is wider than the screen. Helpers live in BaseLevelScene.
RECURRING BUGS to look for:
- iPad VERTICAL VOID: gameplay hugging the bottom with the top half empty dead-sky, OR a thin centered strip with wide empty side margins.
- HUD OVERLAP: a wide instruction/title panel sliding UNDER the top-right PAUSE button, or any panel/control running off a screen edge.
- CRASH/BLANK: an all-black / empty / no-course frame = the scene failed to load or crashed on launch.
- OVER-WIDENED GAPS: a gap or rise beyond the budget above (re-derive EDGE-to-EDGE, platforms are wide — do NOT use center-to-center; over-flagging geometry is the #1 false positive).
IGNORE (Debug-only, never ships): the green "DEBUG ▲" pill (top-left) and the "nodes:N  60.0 fps" counter (bottom-right). Never flag these.
`

const AUDIT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['level', 'renderState', 'ipadVoid', 'hudOverlap', 'completability', 'severity', 'summary'],
  properties: {
    level: { type: 'integer' },
    renderState: { type: 'string', enum: ['ok', 'blank', 'crash'], description: 'blank/crash = scene did not compose (all-black/empty frame)' },
    ipadVoid: { type: 'string', enum: ['none', 'minor', 'severe'], description: 'severe = large unused dead space (top half empty or wide side margins) on iPad' },
    hudOverlap: { type: 'string', enum: ['none', 'minor', 'severe'], description: 'instruction/title/control overlapping the PAUSE button or off-screen, either device' },
    completability: { type: 'string', enum: ['ok', 'suspect', 'broken'], description: 'broken = gap>145 / rise>91 / unreachable exit / stranded, derived edge-to-edge from source' },
    completabilityReason: { type: 'string' },
    iphoneRegression: { type: 'boolean', description: 'true if the iPhone shot looks materially changed/worse than a normal phone layout (iPhone is supposed to be unchanged)' },
    otherIssues: { type: 'array', items: { type: 'string' } },
    severity: { type: 'string', enum: ['clean', 'polish', 'blocker'], description: 'blocker = ship-stopping (crash, uncompletable, or severe void/overlap); polish = real but non-blocking; clean = ship as-is' },
    summary: { type: 'string', description: 'one-paragraph verdict' },
  },
}

const VERIFY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['level', 'confirmed', 'adjustedSeverity', 'reason'],
  properties: {
    level: { type: 'integer' },
    confirmed: { type: 'boolean', description: 'true only if the blocker is unambiguously real and ship-stopping' },
    adjustedSeverity: { type: 'string', enum: ['clean', 'polish', 'blocker'] },
    reason: { type: 'string' },
    suggestedFix: { type: 'string', description: 'concrete fix if confirmed (which helper / what tier count / what to move)' },
  },
}

function shot(idx, dev) { return `${SHOTS}/${dev}/L${String(idx).padStart(2, '0')}.png` }

function auditPrompt(lvl) {
  const kindNote = lvl.kind === 'text'
    ? 'This is a FULL-SCREEN TEXT level (no platform course) — ipadVoid does NOT apply; judge only crash/blank and whether the text + any control fit and read well on iPad.'
    : lvl.kind === 'camera'
    ? 'This is a SCROLLING / CAMERA-FOLLOW level — the course legitimately extends beyond one frame. Do NOT flag off-screen content as void. Judge void only as wide EMPTY side margins or an obviously empty visible band; still judge crash/blank, HUD overlap, and any visible over-wide gap.'
    : 'This is a SINGLE-SCREEN course — on iPad the whole course should be visible and fill the height. Flag severe void if gameplay hugs the bottom with an empty top half, or a thin strip with wide empty side margins.'
  return `You are auditing the native-iPad redesign of Glitched Level ${lvl.idx} (${lvl.title}).

READ THESE THREE FILES (use the Read tool; the .png files are images you can view):
1. iPhone screenshot: ${shot(lvl.idx, 'iphone')}
2. iPad screenshot:   ${shot(lvl.idx, 'ipad')}
3. Source:            ${SRC}/${lvl.file}

LEVEL SPEC: ${lvl.guide}
${kindNote}
${RULES}

TASK: Compare the iPad layout vs the iPhone layout and the source. Decide:
- renderState: did the level visibly compose on BOTH devices? (all-black/empty = blank/crash, a BLOCKER)
- ipadVoid: is there large unused dead space on iPad the redesign should have filled? (per the kind note)
- hudOverlap: does any instruction panel / title / button overlap the top-right PAUSE button or run off any screen edge, on EITHER device?
- completability: scan the SOURCE geometry (platform x/y, gaps, rises) and cross-check the visual — any gap > 145pt EDGE-TO-EDGE or rise > 91pt top-to-top, exit unreachable, platform off-screen, or Bit stranded? Re-derive edge-to-edge (platforms are wide); do NOT over-flag center-to-center distances.
- iphoneRegression: does the iPhone shot look materially changed/worse vs a normal phone layout? (iPhone is supposed to be byte-identical to before.)
- severity: blocker (ship-stopping) / polish (real but non-blocking) / clean.
Be specific and evidence-based. Return the schema object.`
}

function verifyPrompt(lvl, v) {
  return `An auditor flagged Glitched Level ${lvl.idx} (${lvl.title}) as a BLOCKER. Your job is to REFUTE it.

AUDITOR VERDICT: ${JSON.stringify({ renderState: v.renderState, ipadVoid: v.ipadVoid, hudOverlap: v.hudOverlap, completability: v.completability, completabilityReason: v.completabilityReason, summary: v.summary })}

RE-READ (Read tool):
1. iPhone shot: ${shot(lvl.idx, 'iphone')}
2. iPad shot:   ${shot(lvl.idx, 'ipad')}
3. Source:      ${SRC}/${lvl.file}

LEVEL SPEC: ${lvl.guide}
${RULES}

Default to confirmed=FALSE. Over-flagging is the common failure mode: center-to-center vs edge-to-edge gaps; camera/scroll levels look "empty" but extend off-screen; the DEBUG pill / fps counter mistaken for UI bugs; a discovery modal temporarily covering the course. Confirm ONLY if the blocker is unambiguous and genuinely ship-stopping. If confirmed, give a concrete suggestedFix (which BaseLevelScene helper, what tier count, what to move/translate — never widen a gap). Return the schema object.`
}

phase('Audit')
const results = await pipeline(
  LEVELS,
  (lvl) => agent(auditPrompt(lvl), { label: `audit:L${lvl.idx} ${lvl.title}`, phase: 'Audit', schema: AUDIT_SCHEMA })
             .then((v) => ({ lvl, v })),
  ({ lvl, v }) => {
    if (!v) return { lvl: lvl.idx, title: lvl.title, audit: null, confirmed: false }
    if (v.severity !== 'blocker') {
      return { lvl: lvl.idx, title: lvl.title, audit: v, confirmed: v.severity !== 'clean', verify: null }
    }
    return agent(verifyPrompt(lvl, v), { label: `verify:L${lvl.idx} ${lvl.title}`, phase: 'Verify', schema: VERIFY_SCHEMA })
      .then((vr) => ({ lvl: lvl.idx, title: lvl.title, audit: v, verify: vr, confirmed: vr ? vr.confirmed : true }))
  }
)

const clean = results.filter((r) => r && r.audit && r.audit.severity === 'clean')
const polish = results.filter((r) => r && r.audit && r.audit.severity === 'polish')
const blockersConfirmed = results.filter((r) => r && r.verify && r.verify.confirmed)
const blockersRefuted = results.filter((r) => r && r.verify && !r.verify.confirmed)
const failed = results.filter((r) => r && !r.audit)

log(`AUDIT DONE: ${clean.length} clean, ${polish.length} polish, ${blockersConfirmed.length} confirmed blockers, ${blockersRefuted.length} refuted, ${failed.length} agent-failures`)

return {
  summary: {
    clean: clean.map((r) => r.lvl),
    polish: polish.map((r) => ({ level: r.lvl, title: r.title, issues: [r.audit.ipadVoid !== 'none' ? `void:${r.audit.ipadVoid}` : null, r.audit.hudOverlap !== 'none' ? `overlap:${r.audit.hudOverlap}` : null, r.audit.completability !== 'ok' ? `complete:${r.audit.completability}` : null].filter(Boolean), summary: r.audit.summary })),
    confirmedBlockers: blockersConfirmed.map((r) => ({ level: r.lvl, title: r.title, reason: r.verify.reason, fix: r.verify.suggestedFix, audit: r.audit.summary })),
    refutedBlockers: blockersRefuted.map((r) => ({ level: r.lvl, title: r.title, reason: r.verify.reason })),
    agentFailures: failed.map((r) => r.lvl),
  },
  full: results,
}
