export const meta = {
  name: 'glitched-narrative-clue-audit',
  description: 'Audit Glitched storyline order, displayed clue text, t=0 spoiler-timing (no giving the trick away early), and progressive hint escalation for stuck players',
  phases: [
    { title: 'ClueAudit', detail: '34 agents: per-level t=0 spoiler + clue text + hint-escalation wiring' },
    { title: 'Verify', detail: 'adversarial confirm of spoiled-at-t0 and missing-hint findings' },
    { title: 'Narrative', detail: '3 lenses (story arc / level order+difficulty / voice) over the per-level table' },
    { title: 'Synthesize', detail: 'merge into one storyline + clue report' },
  ],
}

const BASE = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad'
const SHOTS = `${BASE}/shots`
const SRC = `${BASE}/glitched-redesign/Glitched/Scenes`

// secret = the part of the solution that is meant to be DISCOVERED and must NOT be
// shown at t=0. An ambiguous/environmental nudge is fine and intended; revealing the
// actual trick/twist/answer at the start is the bug. twist=true => high sensitivity.
const LEVELS = [
  { idx:0,  file:'Level0_BootSequence.swift', title:'Boot',          beat:'W0 cold-open: the system boots; meta-narrator notes your real device time; fourth_wall.ko flagged UNSTABLE.', secret:'the loading bar handle is draggable; the crash is fake ("JUST KIDDING")', twist:false },
  { idx:1,  file:'Level1_Header.swift',        title:'Header',        beat:'W1 first awakening: the UI itself is physical.', secret:'the "LEVEL 1" banner is a draggable object you drop to form a bridge', twist:true },
  { idx:2,  file:'Level2_Wind.swift',          title:'Wind',          beat:'W1: your breath affects the world.', secret:'you blow into the microphone to extend the bridge', twist:false },
  { idx:3,  file:'Level3_Static.swift',        title:'Static',        beat:'W1: noise as a tool, then betrayal.', secret:'the 4th laser is INVERSE — noise ACTIVATES it; you must go SILENT for the last one', twist:true },
  { idx:4,  file:'Level4_Volume.swift',        title:'Volume',        beat:'W1: physical volume buttons matter.', secret:'lower the device volume to keep the wolf asleep AND keep water low', twist:true },
  { idx:5,  file:'Level5_Charging.swift',      title:'Charging',      beat:'W1: feed the device power.', secret:'plug in to charge — a giant plug rises as a platform you ride up', twist:false },
  { idx:6,  file:'Level6_Brightness.swift',    title:'Brightness',    beat:'W1: light reveals.', secret:'raise brightness to reveal platforms, but 95%+ activates burn hazards — find the sweet spot', twist:true },
  { idx:7,  file:'Level7_Screenshot.swift',    title:'Screenshot',    beat:'W1: capture freezes time.', secret:'take a screenshot to freeze the flickering bridge', twist:true },
  { idx:8,  file:'Level8_DarkMode.swift',      title:'Dark Mode',     beat:'W1: appearance flips reality.', secret:'toggle dark/light to swap which platforms are solid; the EXIT needs dark mode', twist:true },
  { idx:9,  file:'Level9_Orientation.swift',   title:'Orientation',   beat:'W1: rotate the device.', secret:'rotate to landscape to widen the corridor past the crusher', twist:true },
  { idx:10, file:'Level10_TimeTravel.swift',   title:'Time Travel',   beat:'W1 finale: leave and time passes.', secret:'background the app for ~5s to let a tree grow into a bridge', twist:true },
  { idx:11, file:'Level11_Notification.swift', title:'Notification',  beat:'W2 control surface: the OS messages you.', secret:'request push notifications and tap them to unlock doors', twist:false },
  { idx:12, file:'Level12_Clipboard.swift',    title:'Clipboard',     beat:'W2: the clipboard crosses the wall.', secret:'copy the password GLITCH3D to the clipboard (do NOT show the password literally at t=0)', twist:true },
  { idx:13, file:'Level13_WiFi.swift',         title:'WiFi',          beat:'W2: connectivity is terrain.', secret:'toggle WiFi to solidify signal platforms / pass signal walls', twist:false },
  { idx:14, file:'Level14_FocusMode.swift',    title:'Focus Mode',    beat:'W2: silence the noise.', secret:'enable Focus/DND to freeze the orbiting hazards', twist:true },
  { idx:15, file:'Level15_LowPower.swift',     title:'Low Power',     beat:'W2: power changes physics.', secret:'toggle Low Power to swap normal/lunar gravity per section', twist:true },
  { idx:16, file:'Level16_ShakeUndo.swift',    title:'Shake Undo',    beat:'W2: shake to rewind.', secret:'shake the device to rewind 3s (limited charges)', twist:true },
  { idx:17, file:'Level17_AirplaneMode.swift', title:'Airplane Mode', beat:'W2: planes lift off.', secret:'enable Airplane Mode to raise platforms to flying positions', twist:true },
  { idx:18, file:'Level18_AppSwitcher.swift',  title:'App Switcher',  beat:'W2: peek between apps.', secret:'peek the app switcher to freeze hazards and reveal trajectory lines', twist:true },
  { idx:19, file:'Level19_FaceID.swift',       title:'Face ID',       beat:'W2: prove your identity.', secret:'authenticate with Face ID to open the vault doors', twist:false },
  { idx:20, file:'Level20_MetaFinale.swift',   title:'Meta Finale',   beat:'W2 BOSS: the system threatens to purge itself.', secret:'WALK INTO the corruption wall (counterintuitive) to trigger the purge that clears it', twist:true },
  { idx:21, file:'Level21_VoiceCommand.swift', title:'Voice Command', beat:'W3 data corruption: speak to the machine.', secret:'speak BRIDGE / OPEN / FLY for the three obstacles', twist:false },
  { idx:22, file:'Level22_BatteryPercent.swift',title:'Battery %',    beat:'W3: less is more.', secret:'the visible exit (far right at 100%) is FAKE; the REAL exit is hidden BELOW stone #5, revealed only when battery<60%', twist:true },
  { idx:23, file:'Level23_DeviceName.swift',   title:'Device Name',   beat:'W3: the game knows you; a doppelganger does not.', secret:'a doppelganger mirrors you; only the real you opens the name-door / reaches the exit', twist:true },
  { idx:24, file:'Level24_StorageSpace.swift', title:'Storage',       beat:'W3: free space dissolves the mass.', secret:'clear the app cache to dissolve the DATA MASS wall', twist:false },
  { idx:25, file:'Level25_TimeOfDay.swift',    title:'Time of Day',   beat:'W3: the clock rules.', secret:'at night the enemies sleep (safe); a 3:33 secret hour is haunted', twist:true },
  { idx:26, file:'Level26_Locale.swift',       title:'Locale',        beat:'W4 reality break: language reshapes the path.', secret:'change device language to unscramble the signs and swap to the correct route', twist:true },
  { idx:27, file:'Level27_VoiceOver.swift',    title:'VoiceOver',     beat:'W4: the unseen is real.', secret:'invisible bridge platforms are always SOLID; VoiceOver reveals where they are', twist:true },
  { idx:28, file:'Level28_AirDrop.swift',      title:'Share Code',    beat:'W4: share and return.', secret:'share the displayed 6-char code, then type it back to open the door', twist:false },
  { idx:29, file:'Level29_TheLie.swift',       title:'The Lie',       beat:'W4: the biggest misdirect.', secret:'THE EXIT WAS BEHIND YOU AT SPAWN the whole time; the right-side exit is fake. Subtitle "NO GIMMICK. JUST WALK." is intentional misdirection — keep it.', twist:true },
  { idx:30, file:'Level30_CreditsFinale.swift',title:'Credits',       beat:'W4 victory-lap: climb the credits.', secret:'the credit lines are platforms; bug enemies are the "remaining bugs"', twist:false },
  { idx:31, file:'Level31_Flashlight.swift',   title:'Flashlight',    beat:'W5 system override: light the dark.', secret:'turn on the real flashlight and tilt the phone to aim the light cone', twist:true },
  { idx:32, file:'Level32_MultiTouch.swift',   title:'Multi-Touch',   beat:'W5: many hands.', secret:'hold multiple pressure plates simultaneously (2 then 3+ fingers) to open gates', twist:true },
  { idx:33, file:'Level33_AppReview.swift',    title:'App Review',    beat:'W5 FINALE: the game begs for a review.', secret:'the review-prompt padlock is a fake gate — it auto-breaks after 10s whether or not you review', twist:true },
]

const HINT_CONTRACT = `
PROGRESSIVE-HINT CONTRACT (BaseLevelScene):
- On death/failure a level should call notePlayerStruggle(); after >=2 struggles AND >=8s it fires showDifficultyHint().
- showDifficultyHint() calls difficultyHintDidShow() (override hook for a STRONGER, pointed contextual hint) and announceObjective(hintText()).
- hintText() -> String? is the bottom-banner hint; default fallback is the generic "Try using your device's features...".
- notePlayerProgress() resets the struggle counter + hintShown so hints re-arm after the player advances.
A level escalates WELL when: it calls notePlayerStruggle() on death, hintText() returns a SPECIFIC useful hint (names the input verb / points at the control), and ideally it overrides difficultyHintDidShow() to surface an even more explicit hint after repeated failure. It escalates POORLY when: it never calls notePlayerStruggle() (so the timer never advances), hintText() is nil/generic, or the hint shown is no more helpful than the t=0 text.
SHARED VOICE: fourth-wall lines should go through GlitchedNarrator (.whisper / .alert / .boss styles), lower-center safe band — not ad-hoc center-screen labels.
IGNORE the green "DEBUG" pill + "nodes/fps" counter (Debug-only). The cyan "SYSTEM ACCESS REQUIRED / GOT IT" box is a PERMISSION prompt, NOT a level clue — don't treat it as a clue.
`

const SPOILER_PRINCIPLE = `
SPOILER-TIMING PRINCIPLE (owner's core concern): a puzzle level must let the player be PUZZLED first. The t=0 screen may show an ambiguous, atmospheric, or category-level nudge ("LOOKS WINDY", "MAKE NOISE TO BLOCK LASERS") but must NOT state the actual trick/twist/answer up front. The reveal should come from play or from the escalating hint AFTER the player struggles. Be especially strict on TWIST levels where the whole point is a discovery (inverse mechanic, fake exit, walk-backwards, walk-INTO the wall, hidden-below, invisible-but-solid, auto-breaking gate).
`

const CLUE_SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','t0Texts','spoilerVerdict','hintEscalation','severity','summary'],
  properties:{
    level:{type:'integer'},
    t0Texts:{type:'array', items:{type:'string'}, description:'every piece of level clue/instruction text visible at the start (from the iPhone t=0 shot + source) — exclude the permission modal and debug overlays'},
    spoilerVerdict:{type:'string', enum:['safe','borderline','spoiled'], description:'does t=0 text reveal the secret/trick? spoiled=gives the answer; borderline=hints too strongly; safe=ambiguous nudge only'},
    spoilerReason:{type:'string'},
    hintEscalation:{type:'string', enum:['good','weak','missing'], description:'good=struggle wires a stronger hint; weak=hint exists but not more helpful / partially wired; missing=no struggle hint or notePlayerStruggle never called'},
    hintWiring:{type:'object', additionalProperties:true, properties:{
      callsNoteStruggle:{type:'boolean'}, hintTextUseful:{type:'boolean'}, hasDifficultyHintOverride:{type:'boolean'}, escalatesHelpfully:{type:'boolean'}
    }},
    hintReason:{type:'string'},
    textIssues:{type:'array', items:{type:'string'}, description:'typos, broken/clipped text, voice inconsistency, unclear wording'},
    severity:{type:'string', enum:['clean','polish','blocker'], description:'blocker = spoils a twist at t=0 OR a stuck player can never get an escalated hint; polish = real but minor; clean = good as-is'},
    summary:{type:'string'},
  }
}

const VERIFY_SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','confirmed','reason'],
  properties:{
    level:{type:'integer'},
    confirmed:{type:'boolean', description:'true only if the spoiler/missing-hint finding is unambiguously real'},
    adjustedSeverity:{type:'string', enum:['clean','polish','blocker']},
    reason:{type:'string'},
    suggestedFix:{type:'string', description:'concrete fix: which t=0 text to soften/remove, or what hintText()/difficultyHintDidShow()/notePlayerStruggle() wiring to add'},
  }
}

function shot(idx){ return `${SHOTS}/iphone/L${String(idx).padStart(2,'0')}.png` }

function cluePrompt(l){
  return `You are auditing Glitched Level ${l.idx} (${l.title}) for CLUE TEXT, SPOILER TIMING, and PROGRESSIVE HINTS.

READ (Read tool):
1. iPhone t=0 screenshot (what text shows at the START): ${shot(l.idx)}
2. Source: ${SRC}/${l.file}

STORY BEAT: ${l.beat}
THE SECRET (must be discovered, NOT given away at t=0): ${l.secret}
TWIST LEVEL: ${l.twist ? 'YES — be strict; the discovery is the whole point.' : 'no — standard mechanic.'}
${SPOILER_PRINCIPLE}
${HINT_CONTRACT}

DO THREE THINGS:
1. CLUE TEXT: list every level clue/instruction line shown at t=0 (read it off the screenshot AND find the strings in source — instruction panels, placards, titles, narrator lines, labels). Flag typos, clipped/overflowing text, and voice inconsistencies (textIssues).
2. SPOILER TIMING: does any t=0 text reveal THE SECRET above? Decide safe / borderline / spoiled, with the exact offending line in spoilerReason.
3. PROGRESSIVE HINTS: read the source — does it call notePlayerStruggle() on death? does hintText() return a SPECIFIC useful hint? does it override difficultyHintDidShow() for a stronger hint? Will a STUCK player actually get MORE help over time? Decide good / weak / missing and fill hintWiring.
severity: blocker if a twist is spoiled at t=0 OR a stuck player can never get an escalated hint. Return the schema object.`
}

function verifyPrompt(l, v){
  return `An auditor flagged Glitched Level ${l.idx} (${l.title}). REFUTE it unless unambiguous.
FINDING: spoiler=${v.spoilerVerdict} ("${v.spoilerReason||''}"), hints=${v.hintEscalation} ("${v.hintReason||''}"), severity=${v.severity}.
THE SECRET to protect: ${l.secret}
RE-READ: t=0 shot ${shot(l.idx)} ; source ${SRC}/${l.file}
${SPOILER_PRINCIPLE}
${HINT_CONTRACT}
Default confirmed=FALSE. Common false positives: treating an intended ATMOSPHERIC nudge as a spoiler; treating the permission modal as a clue; missing a notePlayerStruggle() call that IS present under another name; a hint that genuinely does escalate. Confirm only if real. If confirmed, give a concrete suggestedFix. Return the schema object.`
}

phase('ClueAudit')
const perLevel = await pipeline(
  LEVELS,
  (l) => agent(cluePrompt(l), { label:`clue:L${l.idx} ${l.title}`, phase:'ClueAudit', schema: CLUE_SCHEMA }).then(v => ({ l, v })),
  ({ l, v }) => {
    if (!v) return { lvl:l.idx, title:l.title, audit:null, confirmed:false }
    const needsVerify = v.severity === 'blocker' || v.spoilerVerdict === 'spoiled' || v.hintEscalation === 'missing'
    if (!needsVerify) return { lvl:l.idx, title:l.title, audit:v, confirmed: v.severity !== 'clean', verify:null }
    return agent(verifyPrompt(l, v), { label:`verify:L${l.idx} ${l.title}`, phase:'Verify', schema: VERIFY_SCHEMA })
      .then(vr => ({ lvl:l.idx, title:l.title, audit:v, verify:vr, confirmed: vr ? vr.confirmed : true }))
  }
)

// Compact per-level table for the narrative lenses.
const table = perLevel.filter(Boolean).map(r => ({
  level:r.lvl, title:r.title,
  t0:r.audit?.t0Texts || [],
  spoiler:r.audit?.spoilerVerdict, hints:r.audit?.hintEscalation,
  textIssues:r.audit?.textIssues || [],
  confirmedSpoiler: r.verify ? (r.verify.confirmed && r.audit?.spoilerVerdict !== 'safe') : (r.audit?.spoilerVerdict === 'spoiled'),
})).sort((a,b)=>a.level-b.level)

phase('Narrative')
const GUIDE_ORDER = LEVELS.map(l => `L${l.idx} ${l.title} [${l.beat}]`).join('\n')
const LENSES = [
  { key:'arc', q:'STORY ARC: Does the fourth-wall meta-narrative escalate coherently W0 boot -> W1 hardware awakening -> W2 control surface (boss L20 purge) -> W3 data corruption -> W4 reality break (incl. the L29 "The Lie") -> W5 system override -> L33 App-Review finale? Identify narrative gaps, beats that land out of order, or a level whose story role is unclear/misplaced. Note specifically: does L30 Credits fire BEFORE the true finale (L33)? Is the W2 boss (L20) positioned right?' },
  { key:'order', q:'LEVEL ORDER & DIFFICULTY: Is the teaching/difficulty curve sensible in this order (mechanic complexity, twist density)? Are twist levels spaced so the player is not twist-fatigued? Any level that should move earlier/later? Is the free-slice (W0+W1, levels 0-10) a satisfying self-contained teaser that earns the paid worlds?' },
  { key:'voice', q:'VOICE & CLUE CONSISTENCY: Across the per-level t=0 texts and narrator lines, is the fourth-wall voice consistent (tone, person, GlitchedNarrator usage)? Are there levels whose clue text breaks character, is generic, or contradicts the meta-narrative? Aggregate the recurring text-quality issues.' },
]
const lensFindings = await parallel(LENSES.map(L => () =>
  agent(`You are the ${L.key.toUpperCase()} lens reviewing the WHOLE Glitched campaign (34 levels in this order):
${GUIDE_ORDER}

PER-LEVEL CLUE/HINT AUDIT TABLE (t0 = text shown at start; spoiler/hints verdicts):
${JSON.stringify(table, null, 1)}

${L.q}

Return a concise findings list: each item = {level (or "arc"), issue, severity (blocker|polish|idea), fix}. Be specific and reference levels by number.`,
    { label:`lens:${L.key}`, phase:'Narrative', schema:{ type:'object', additionalProperties:false, required:['lens','findings'], properties:{ lens:{type:'string'}, findings:{type:'array', items:{ type:'object', additionalProperties:false, required:['where','issue','severity'], properties:{ where:{type:'string'}, issue:{type:'string'}, severity:{type:'string', enum:['blocker','polish','idea']}, fix:{type:'string'} } } } } } })
))

phase('Synthesize')
const confirmedSpoilers = perLevel.filter(r => r && r.confirmed && r.audit && r.audit.spoilerVerdict !== 'safe' && (r.verify ? r.verify.confirmed : true)).map(r => ({ level:r.lvl, title:r.title, reason:r.audit.spoilerReason, fix:r.verify?.suggestedFix }))
const missingHints = perLevel.filter(r => r && r.audit && r.audit.hintEscalation === 'missing' && (r.verify ? r.verify.confirmed : true)).map(r => ({ level:r.lvl, title:r.title, reason:r.audit.hintReason, wiring:r.audit.hintWiring, fix:r.verify?.suggestedFix }))
const weakHints = perLevel.filter(r => r && r.audit && r.audit.hintEscalation === 'weak').map(r => ({ level:r.lvl, title:r.title, reason:r.audit.hintReason }))
const textIssues = perLevel.filter(r => r && r.audit && (r.audit.textIssues||[]).length).map(r => ({ level:r.lvl, title:r.title, issues:r.audit.textIssues }))

log(`CLUE AUDIT: ${confirmedSpoilers.length} confirmed t=0 spoilers, ${missingHints.length} missing-hint, ${weakHints.length} weak-hint, ${textIssues.length} levels with text issues`)

return {
  spoilersAtT0: confirmedSpoilers,
  missingProgressiveHints: missingHints,
  weakProgressiveHints: weakHints,
  textIssues,
  narrative: lensFindings.filter(Boolean),
  perLevelTable: table,
}
