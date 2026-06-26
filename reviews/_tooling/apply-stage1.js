export const meta = {
  name: 'glitched-apply-stage1',
  description: 'Apply de-spoil copy + progressive-hint safety net + hint wiring + text bugs to Glitched (one agent per file, parallel-safe)',
  phases: [
    { title: 'Core', detail: 'BaseLevelScene no-progress hint safety-net' },
    { title: 'Apply', detail: 'one agent per scene file: de-spoil t=0, escalated hint, notePlayerStruggle wiring' },
  ],
}

const SRC = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched'

const SHARED = `
GLOBAL RULES:
- Work ONLY in the file(s) assigned to you. Do NOT touch geometry, physics, platform positions, the device mechanic, or the iPad-layout (isWideCanvas) code — this pass is clue TEXT + hint TIMING only.
- The new t=0 lines must replace the EXPLICIT instruction text but KEEP any already-good atmospheric line noted. Match the existing SKLabelNode/panel styling (font, size, color, position) of the line you replace; if a new line is longer, widen the plate/panel or split across the existing label slots so nothing clips.
- hintText() is the EARNED reveal shown after struggle — set it to the provided newHint verbatim (or very close).
- PROGRESSIVE HINT WIRING: ensure the level's death/failure path calls notePlayerStruggle() (so repeated failure escalates the hint), and that a clear forward-progress moment calls notePlayerProgress() if one exists. If handleDeath()/failLevel already calls it, leave it.
- Keep iPhone and iPad identical for clue text (clue text is shared, not device-gated).
- After editing, the file MUST still compile (balanced braces, valid Swift). Return a precise summary of every edit.
`

// Each level: newT0 = the replacement/kept t=0 lines (atmospheric); newHint = the escalated hint; note = specifics.
const LEVELS = [
  { idx:3,  file:'Scenes/Level3_Static.swift', newT0:['THIS ONE LISTENS DIFFERENTLY.'], newHint:'The first three lasers die when you make noise — but the dashed 4th is wired backwards: noise ARMS it. Hold your breath and let the room go SILENT to cross the last barrier.', note:'In addInverseLaserClue(on:) (~lines 760-794) replace the "INVERSE" label text with "THIS ONE LISTENS DIFFERENTLY." and DELETE the second "QUIET = SAFE" label (single line only). Keep the pulse action + the main "MAKE NOISE / TO BLOCK LASERS" panel + the "THE NEIGHBORS..." aside. Widen the plate if needed for the longer line. handleDeath already calls notePlayerStruggle — keep it.' },
  { idx:4,  file:'Scenes/Level4_Volume.swift', newT0:['KEEP IT QUIET','IT SLEEPS. THE WATER LISTENS.',"DON'T MAKE A SOUND IT CAN HEAR."], newHint:"Press your device's Volume-Down button. The quieter you go, the deeper it sleeps — and the lower the water stays. Loud wakes it and floods you both.", note:'Replace the "Lower volume — loud noises wake the wolf" instruction line and DELETE the persistent "TOO LOUD = FLOOD" label (~:271). Keep "KEEP IT QUIET". Add notePlayerStruggle() in handleDeath (~:1544).' },
  { idx:6,  file:'Scenes/Level6_Brightness.swift', newT0:["I CAN'T SEE EITHER, YOU KNOW.",'THE DARK IS HIDING THE FLOOR FROM BOTH OF US.'], newHint:'Raise your device brightness slider near the top to make the ghost platforms solid — but pull back before full: max brightness lights a burn hazard.', note:'Delete the "NOT TOO BRIGHT  ~80%" caption (~:1331). De-emphasize/remove the pre-drawn sweet-spot band on the LUX bar (~:1216-1226) — only show it AFTER a first burn, or drop it. Add notePlayerStruggle() in handleDeath (~:1571).' },
  { idx:7,  file:'Scenes/Level7_Screenshot.swift', newT0:['SOME MOMENTS REFUSE TO MOVE...','THE BRIDGE ONLY EXISTS WHEN NOTHING IS LOOKING. SO LOOK.','CATCH IT BEFORE IT FORGETS ITSELF.'], newHint:'Capture this moment and it cannot move. Take a screenshot — press the Side button + Volume Up — to pin the bridge solid long enough to cross.', note:'Replace the explicit "SCREENSHOT"/"TO FREEZE"/"PRESS SIDE + VOLUME UP" panel lines (~:918/925/935) with the new tease. Keep "SOME MOMENTS REFUSE TO MOVE...". Add notePlayerStruggle() in handleDeath (~:1292).' },
  { idx:8,  file:'Scenes/Level8_DarkMode.swift', newT0:["NIGHT AND DAY DON'T AGREE ON WHAT'S REAL.",'WHAT HOLDS YOU IN ONE IS A RUMOR IN THE OTHER.','THE DOOR ONLY TRUSTS THE DARK.'], newHint:'Swipe down from the top-right and tap Dark Mode on/off to swap which platforms are solid. The exit door only unlocks while you are in dark mode.', note:'Replace "MOON PLATFORMS: SOLID IN DARK" / "SUN PLATFORMS: SOLID IN LIGHT" rule lines. Add notePlayerStruggle() in handleDeath (~:1675).' },
  { idx:9,  file:'Scenes/Level9_Orientation.swift', newT0:["UP IS A MATTER OF OPINION...","THIS HALL WASN'T BUILT FOR YOU."], newHint:'Rotate the device to landscape — turn the phone sideways and the corridor widens enough to pass the crusher.', note:'Keep the "UP IS A MATTER OF OPINION..." discovery line. Replace the instruction panel "ROTATE"/"LANDSCAPE" + the early "TURN YOUR DEVICE SIDEWAYS" cue with the single in-voice "THIS HALL WASN\'T BUILT FOR YOU.". Add notePlayerStruggle() in handleDeath (~:1424).' },
  { idx:12, file:'Scenes/Level12_Clipboard.swift', newT0:['IT REMEMBERS WHAT YOU LAST HELD.','THE KEY IS NOT HERE. IT IS SOMEWHERE YOU ALREADY WERE.'], newHint:'Copy the password GLITCH3D to your clipboard (grab it anywhere outside the level), come back, and tap PASTE PASSWORD on the terminal.', note:'CRITICAL: the line printing "COPY: GLITCH3D" (~:485) prints the literal password — replace it so the password is NOT shown (show a redacted/scrambled "PASSWORD: ▓▓▓▓▓▓▓▓" or the new tease). Add notePlayerStruggle() in handleDeath (~:697).' },
  { idx:14, file:'Scenes/Level14_FocusMode.swift', newT0:['THE NOISE NEVER STOPS...','UNLESS YOU LET IT.','SO HOW QUIET CAN YOU MAKE YOURSELF?'], newHint:'Turn on Focus / Do Not Disturb in iOS Control Center (the crescent-moon toggle) — it freezes every spike mid-orbit and unlocks the door. Stuck without it? Tap CAN\'T DO THIS? in the bottom corner.', note:'Replace the 3rd panel line "ENABLE FOCUS / DO NOT DISTURB TO FREEZE THE CHAOS" (~:736) with "SO HOW QUIET CAN YOU MAKE YOURSELF?". Keep lines 1-2. Add notePlayerStruggle() in handleDeath (~:906).' },
  { idx:15, file:'Scenes/Level15_LowPower.swift', newT0:['THE BATTERY IS DYING.','EVERYTHING GETS LIGHTER WHEN I LET GO.'], newHint:'The POWER button (lower-right) flips gravity. Tap it to read POWER OFF and float the wide chasm; tap again to read POWER ON and weigh yourself down to thread the narrow drop.', note:'Replace "CONSERVE ENERGY. FLOAT." + "TAP POWER TO GO LIGHT..." panel lines. This newHint ALSO fixes the bug where hintText misdirected to iOS Settings — it must name the on-screen POWER button, NOT Settings. Add notePlayerStruggle() in handleDeath (~:824).' },
  { idx:16, file:'Scenes/Level16_ShakeUndo.swift', newT0:['MISTAKES CAN BE UNMADE','BUT NOT FOREVER','REGRET HAS A GRIP. USE IT.'], newHint:'Shake the device to rewind the last 3 seconds — the undo counter (top-left) shows how many rewinds you have left.', note:'Replace "SHAKE TO REWIND TIME" with "REGRET HAS A GRIP. USE IT.". Keep "MISTAKES CAN BE UNMADE"/"BUT NOT FOREVER". Add notePlayerStruggle() in handleDeath (~:1073).' },
  { idx:17, file:'Scenes/Level17_AirplaneMode.swift', newT0:['THE GROUND IS NO PLACE TO STAY.','CUT THE WORLD LOOSE. LET IT RISE.','EVERYTHING TETHERED IS WAITING TO LEAVE.'], newHint:'Turn ON Airplane Mode — tap the plane icon or swipe Control Center down — to raise the platforms into their flying positions.', note:'Replace the flat "TURN ON AIRPLANE MODE — TAP THE PLANE OR USE CONTROL CENTER" line with "EVERYTHING TETHERED IS WAITING TO LEAVE.". Keep the two poetic lines. notePlayerStruggle already wired — keep it.' },
  { idx:18, file:'Scenes/Level18_AppSwitcher.swift', newT0:['THE WORLD HOLDS','ITS BREATH WHEN','YOU LOOK AWAY','SO. STOP WATCHING.'], newHint:'Swipe up slightly — just enough to peek the App Switcher, not leave. Everything stops while you\'re half-gone, and the spikes\' paths draw themselves. Read them, then drop back in.', note:'Replace "SWIPE UP TO PEEK & FREEZE TIME" (~:539) with "SO. STOP WATCHING.". Keep the 3 poetic lines. Add notePlayerStruggle() in handleDeath (~:752).' },
  { idx:20, file:'Scenes/Level20_MetaFinale.swift', newT0:['THE CORRUPTION GATE','CORRUPTED DATA BLOCKS THE EXIT','IT WANTS YOU TO TURN BACK. EVERYTHING DOES.'], newHint:'There is no path around the corruption. Stop trying to avoid it — hold toward the wall and push Bit INTO the blocks. The contact is the purge.', note:'Replace the hintLabel "WALK INTO THE CORRUPTION TO PURGE IT" (~:616) with "IT WANTS YOU TO TURN BACK. EVERYTHING DOES." and the progressSavedLabel "TOUCH THE WALL TO BEGIN PURGE" with neutral non-instruction text. Keep "THE CORRUPTION GATE"/"CORRUPTED DATA BLOCKS THE EXIT". Add notePlayerStruggle() in handleDeath (~:1155). (Voice routing to GlitchedNarrator handled in a later pass — text only here.)' },
  { idx:25, file:'Scenes/Level25_TimeOfDay.swift', newT0:['THE WORLD CHANGES WITH THE CLOCK',"SOMETHING GUARDS THAT LEDGE. IT WON'T ALWAYS BE WATCHING."], newHint:'The guard on that ledge only moves in daylight. Tap CYCLE TIME until it reads NIGHT, then cross while it sleeps.', note:'Replace "TAP CYCLE TIME TO SLEEP THE ENEMIES" (~:621) with the new line 2. Keep line 1. Add notePlayerStruggle() in handleDeath (~:991).' },
  { idx:26, file:'Scenes/Level26_Locale.swift', newT0:['THE SIGNS ARE TRYING TO TELL YOU SOMETHING.','BUT NOT IN A TONGUE THIS DEVICE STILL REMEMBERS.'], newHint:'The signs aren\'t broken, they\'re foreign. Open Settings > General > Language & Region and switch your device to a different language, then come back and read what the path was hiding.', note:'Replace the headline "CHANGE YOUR LANGUAGE TO READ" (~:553). Keep the scrambled-glyph line + the small revert hint. Add notePlayerStruggle() in handleDeath (~:798).' },
  { idx:27, file:'Scenes/Level27_VoiceOver.swift', newT0:["THE GAP DOESN'T CARE THAT YOU SEE IT.",'BUT SOMETHING HERE IS LISTENING FOR YOU.',"A PATH EXISTS ONLY ONCE IT'S NAMED ALOUD."], newHint:'Toggle VoiceOver in Settings — or tap the accessibility button at the bottom-left — to phase the path in. Once it\'s solid it STAYS solid: turn VoiceOver back off and cross with normal taps. Land only on the SOLID stones.', note:'Replace the panel "THE BRIDGE ISN\'T THERE UNTIL YOU PERCEIVE IT. TOGGLE VOICEOVER — OR TAP THE ACCESSIBILITY BUTTON." (~:697-716). Route the ad-hoc death-hint banners through the existing pattern if trivial, else leave. Add notePlayerStruggle() (level tracks its own deathCount ~:939 — ALSO call notePlayerStruggle() there).' },
  { idx:28, file:'Scenes/Level28_AirDrop.swift', newT0:['THE CODE IS SCRAMBLED.',"I CAN'T READ MYSELF IN HERE.",'TAKE ME SOMEWHERE I CAN.'], newHint:'Tap SHARE TO DECODE and send the transmission to yourself — AirDrop, Messages, or Notes. What arrives is the real code. Then key those 6 symbols back in (the keypad is salted with decoys).', note:'Replace "SHARE THE TRANSMISSION TO DECODE IT, THEN KEY THE DECODED CODE BACK IN." with lines 2-3. Keep "THE CODE IS SCRAMBLED.". notePlayerStruggle already on wrong-submit — also add to any death path.' },
  { idx:31, file:'Scenes/Level31_Flashlight.swift', newT0:["IT'S DARK DOWN HERE.","I CAN'T SEE A THING FROM IN HERE — CAN YOU?"], newHint:'You\'re holding a light, you know. Switch on the phone\'s flashlight. Stand the phone upright to throw the beam far ahead — tilt it flat to pool the light on the floor and catch the pits.', note:'Replace "TURN ON YOUR FLASHLIGHT" panel (~:1326-1339) + the tilt line with the new tease. Add notePlayerStruggle() in handleDeath/failLevel path.' },
  { idx:32, file:'Scenes/Level32_MultiTouch.swift', newT0:['CONTACT REQUIRED','ONE OF YOU IS NOT ENOUGH.'], newHint:'Hold every glowing contact pad in a group down at once and KEEP holding — two pads for the first gate, three for the second, four for the last — then walk Bit through while they stay pressed.', note:'Replace subtitle "MULTI-TOUCH" (~:191) with "CONTACT REQUIRED" and the panel "PLACE YOUR FINGERS ON THE NODES" (~:846) with "ONE OF YOU IS NOT ENOUGH.". Standardize the term to "contact/pad" (not nodes/fingers) in player-facing copy. Add notePlayerStruggle() in handleDeath (~:1299).' },
]

// Hint-wiring-only (no t=0 spoiler, but the escalation path is dead/weak).
const HINT_ONLY = [
  { idx:11, file:'Scenes/Level11_Notification.swift', note:'Add notePlayerStruggle() to the death/no-progress path so the existing hintText() can fire. Do NOT change clue text.' },
  { idx:21, file:'Scenes/Level21_VoiceCommand.swift', note:'handleDeath (~:1094) respawns without notePlayerStruggle() — add it. Optionally make hintText() mention the FLY-must-come-last ordering. No t=0 text change.' },
  { idx:23, file:'Scenes/Level23_DeviceName.swift', note:'handleDeath (~:1019) never calls notePlayerStruggle() — add it. No t=0 text change. (Its HUD overlap is fixed in a later geometry pass.)' },
  { idx:29, file:'Scenes/Level29_TheLie.swift', note:'Good hint string but dead-wired: handleDeath (~:854) never calls notePlayerStruggle() — add it so "Are you sure the exit is ahead?" can fire. Do NOT change the misdirect copy.' },
]

const APPLY_SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','file','summary'],
  properties:{
    level:{type:'integer'},
    file:{type:'string'},
    t0Replaced:{type:'boolean'},
    hintUpdated:{type:'boolean'},
    struggleWired:{type:'boolean'},
    summary:{type:'string', description:'precise list of edits made (old -> new, line refs)'},
    risks:{type:'string', description:'any compile risk, clipping risk, or thing to double-check'},
  },
}

function applyPrompt(l){
  return `Apply the de-spoil + hint changes to Glitched Level ${l.idx}.
FILE: ${SRC}/${l.file}${l.idx===1?` AND ${SRC}/UI/LevelHeaderHUD.swift`:''}
${SHARED}
NEW t=0 LINES (atmospheric — replace the explicit instruction, keep noted good lines): ${JSON.stringify(l.newT0)}
NEW ESCALATED HINT (set hintText() to this): "${l.newHint}"
SPECIFICS: ${l.note}
Read the file, make the edits with the Edit tool, and return the schema object.`
}

function hintOnlyPrompt(l){
  return `Wire the progressive-hint safety net into Glitched Level ${l.idx}.
FILE: ${SRC}/${l.file}
${SHARED}
TASK (NO clue-text change): ${l.note}
Read the file, add the notePlayerStruggle() call (and notePlayerProgress() on a clear progress moment if one exists and is missing), and return the schema object (t0Replaced=false).`
}

phase('Core')
const core = await agent(
`Add a NO-PROGRESS HINT SAFETY-NET to BaseLevelScene so every level escalates a hint for a stuck player, even if it never calls notePlayerStruggle().
FILE: ${SRC}/Scenes/BaseLevelScene.swift
CONTEXT: today showDifficultyHintIfNeeded() only fires when a subclass calls notePlayerStruggle() >=2 times after >=8s (notePlayerStruggle ~:716; showDifficultyHintIfNeeded ~:737; showDifficultyHint ~:753; notePlayerProgress resets struggleCount+hintShown ~:710; playStartedAt set in runIntroSequence ~:477; there is an update/updatePlaying loop). 27 of 33 levels never call notePlayerStruggle(), so their hintText() can never fire.
TASK: add a time-based fallback — track the timestamp of the last forward progress (set it in notePlayerProgress() and at play start). In the scene update loop (the base-class update path that already computes deltaTime), if the level is in .playing, no difficulty hint has shown yet (hintShown==false), and it has been >= ~22 seconds since the last progress/struggle reset, call showDifficultyHintIfNeeded(). Respect the existing extendedHintTimers accessibility setting (lengthen the timeout when set, mirroring how the current path uses it). Do NOT remove the existing struggle-count path (it should still fire FASTER on repeated death). Keep it minimal and ensure it compiles. Return a precise summary of the edit.`,
  { label:'core:BaseLevelScene safety-net', phase:'Core', schema: APPLY_SCHEMA }
)

phase('Apply')
const despoil = await parallel(LEVELS.map(l => () =>
  agent(applyPrompt(l), { label:`despoil:L${l.idx}`, phase:'Apply', schema: APPLY_SCHEMA })
))
const hintWire = await parallel(HINT_ONLY.map(l => () =>
  agent(hintOnlyPrompt(l), { label:`hint:L${l.idx}`, phase:'Apply', schema: APPLY_SCHEMA })
))

const all = [core, ...despoil, ...hintWire].filter(Boolean)
log(`STAGE 1 APPLIED: ${all.length} files edited`)
return { edits: all, risks: all.filter(e => e.risks && e.risks.length > 3).map(e => ({ level:e.level, risk:e.risks })) }
