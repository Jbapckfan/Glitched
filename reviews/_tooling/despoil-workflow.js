export const meta = {
  name: 'glitched-despoil-copy',
  description: 'Draft before/after t=0 clue copy for the 20 spoiled Glitched levels: atmospheric in-voice nudge at start, explicit instruction demoted to the escalated stuck-player hint',
  phases: [
    { title: 'Draft', detail: '20 agents draft new t=0 nudge + reworked hint per spoiled level' },
    { title: 'VoicePass', detail: 'one agent checks persona consistency + over/under-reveal across all 20' },
  ],
}

const SRC = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched/Scenes'

const LEVELS = [
  { idx:1,  file:'Level1_Header.swift',        title:'Header',        secret:'the "LEVEL 1" banner is a draggable object you pull DOWN to form a bridge over the pit', spoiler:'a "≡ DRAG DOWN ⌄" affordance label under the LEVEL 1 banner (NOTE: rendered by the SwiftUI HUD, not this scene file — flag where the change must go)' },
  { idx:3,  file:'Level3_Static.swift',        title:'Static',        secret:'the 4th laser is INVERSE — noise ARMS it; you must go SILENT for the last barrier', spoiler:'an in-world placard on the 4th emitter reading "INVERSE" / "QUIET = SAFE" (addInverseLaserClue). The main "MAKE NOISE TO BLOCK LASERS" panel is an acceptable category nudge; the QUIET=SAFE placard is the spoiler' },
  { idx:4,  file:'Level4_Volume.swift',        title:'Volume',        secret:'LOWER the device volume to keep the wolf asleep AND keep the water low', spoiler:'"KEEP IT QUIET" + "Lower volume — loud noises wake the wolf" instruction + a persistent "TOO LOUD = FLOOD" label' },
  { idx:6,  file:'Level6_Brightness.swift',    title:'Brightness',    secret:'raise brightness to reveal platforms, but 95%+ activates a burn hazard — find the high-but-not-max sweet spot', spoiler:'a "NOT TOO BRIGHT  ~80%" caption + a pre-drawn sweet-spot band on the LUX bar' },
  { idx:7,  file:'Level7_Screenshot.swift',    title:'Screenshot',    secret:'take a screenshot to freeze the flickering bridge', spoiler:'a persistent panel "SCREENSHOT" + "TO FREEZE" + "PRESS SIDE + VOLUME UP". The atmospheric "SOME MOMENTS REFUSE TO MOVE..." line is fine to keep' },
  { idx:8,  file:'Level8_DarkMode.swift',      title:'Dark Mode',     secret:'toggle dark/light to swap which platforms are solid; the EXIT needs dark mode', spoiler:'panel lines "MOON PLATFORMS: SOLID IN DARK" / "SUN PLATFORMS: SOLID IN LIGHT"' },
  { idx:9,  file:'Level9_Orientation.swift',   title:'Orientation',   secret:'rotate the device to landscape to widen the corridor past the crusher', spoiler:'an instruction panel "ROTATE" / "LANDSCAPE" plus an early "TURN YOUR DEVICE SIDEWAYS" cue — the action is stated three ways' },
  { idx:12, file:'Level12_Clipboard.swift',    title:'Clipboard',     secret:'copy the password GLITCH3D to the clipboard, then the terminal reads it', spoiler:'a center-screen label literally printing "COPY: GLITCH3D" — hands over BOTH the verb and the literal password. Show a scrambled/redacted password instead, never the answer' },
  { idx:14, file:'Level14_FocusMode.swift',    title:'Focus Mode',    secret:'enable Focus / Do Not Disturb to freeze the orbiting hazards', spoiler:'panel line "ENABLE FOCUS / DO NOT DISTURB TO FREEZE THE CHAOS"' },
  { idx:15, file:'Level15_LowPower.swift',     title:'Low Power',     secret:'toggle Low Power (the on-screen POWER button) to swap normal/lunar gravity per section', spoiler:'panel "CONSERVE ENERGY. FLOAT." + "TAP POWER TO..."; ALSO the hint misdirects to iOS Settings instead of the on-screen POWER button (fix the hint to name the in-scene button)' },
  { idx:16, file:'Level16_ShakeUndo.swift',    title:'Shake Undo',    secret:'shake the device to rewind 3s (limited charges)', spoiler:'panel line "SHAKE TO REWIND TIME". The atmospheric "MISTAKES CAN BE UNMADE" / "BUT NOT FOREVER" lines are good to keep' },
  { idx:17, file:'Level17_AirplaneMode.swift', title:'Airplane Mode', secret:'enable Airplane Mode to raise the platforms to their flying positions', spoiler:'panel "TURN ON AIRPLANE MODE — TAP THE PLANE OR USE CONTROL CENTER". The poetic "CUT THE WORLD LOOSE. LET IT RISE." line is good to keep' },
  { idx:18, file:'Level18_AppSwitcher.swift',  title:'App Switcher',  secret:'peek the app switcher (swipe up slightly) to freeze hazards and reveal trajectory lines', spoiler:'panel line "SWIPE UP TO PEEK & FREEZE TIME". The poetic "THE WORLD HOLDS ITS BREATH WHEN YOU LOOK AWAY" is good to keep' },
  { idx:20, file:'Level20_MetaFinale.swift',   title:'Meta Finale',   secret:'counterintuitively WALK INTO the corruption wall to trigger the purge that clears it', spoiler:'multiple verbatim statements: hintLabel "WALK INTO THE CORRUPTION TO PURGE IT", instruction text3, and a "TOUCH THE WALL" progress label (two verbs for the same action). This is a W2 BOSS — keep dread, hide the counterintuitive solution' },
  { idx:25, file:'Level25_TimeOfDay.swift',    title:'Time of Day',   secret:'at night the enemies sleep (safe); cycling to night makes the guarded landing passable', spoiler:'panel line "TAP CYCLE TIME TO SLEEP THE ENEMIES"' },
  { idx:26, file:'Level26_Locale.swift',       title:'Locale',        secret:'change the device language to unscramble the signs and swap to the correct route', spoiler:'panel headline "CHANGE YOUR LANGUAGE TO READ"' },
  { idx:27, file:'Level27_VoiceOver.swift',    title:'VoiceOver',     secret:'invisible bridge platforms are ALWAYS solid; VoiceOver reveals where they are', spoiler:'panel "THE BRIDGE ISN\'T THERE UNTIL YOU PERCEIVE IT. TOGGLE VOICEOVER — OR TAP THE ACCESSIBILITY BUTTON"' },
  { idx:28, file:'Level28_AirDrop.swift',      title:'Share Code',    secret:'share the displayed 6-char code, then type it back on the keypad to open the door', spoiler:'panel "SHARE THE TRANSMISSION TO DECODE IT, THEN KEY THE DECODED CODE BACK IN" (full procedure verbatim)' },
  { idx:31, file:'Level31_Flashlight.swift',   title:'Flashlight',    secret:'turn on the real device flashlight and tilt the phone to aim the light cone', spoiler:'panel "TURN ON YOUR FLASHLIGHT" + a second tilt line. Some reveal is OK (the cave is literally invisible without light) — soften to a nudge, keep playable' },
  { idx:32, file:'Level32_MultiTouch.swift',   title:'Multi-Touch',   secret:'hold multiple pressure plates simultaneously (2 then 3+ fingers) while inching Bit forward', spoiler:'panel "PLACE YOUR FINGERS ON THE NODES" + "MULTI-TOUCH" subtitle. Standardize one term (nodes/fingers/contacts drift elsewhere)' },
]

const VOICE = `
GLITCHED VOICE: a corrupted-OS persona that has become aware of YOU, the operator. Tone: eerie, intimate, dryly funny, a little menacing — never a help manual, never a tutorial pop-up. Fourth-wall lines route through GlitchedNarrator (.whisper / .alert / .boss). Line-art terminal aesthetic, uppercase Menlo for system text.
THE DE-SPOIL RULE:
- newT0 = what shows at the START. It must TEASE, not TELL: atmospheric / sensory / in-character. It may hint the CATEGORY or the feeling, but must NOT name the input verb, the device toggle, the answer, or the twist. (Bad: "TURN ON AIRPLANE MODE". Good: "THE GROUND IS NO PLACE TO STAY.") Keep any existing good atmospheric line; cut the explicit instruction line.
- newHint = the EARNED reveal, shown only after the player struggles (hintText()). It SHOULD be concrete and name the exact gesture/control/ordering — it is the payoff for being stuck, and must be MORE specific than newT0 (not a paraphrase of it).
- difficultyHint (optional) = an even stronger, pointed contextual nudge for difficultyHintDidShow() after repeated failure.
- Preserve completability and the device mechanic exactly; this is copy/timing only.
`

const DRAFT_SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','newT0','newHint'],
  properties:{
    level:{type:'integer'},
    title:{type:'string'},
    currentT0:{type:'array', items:{type:'string'}, description:'the exact spoiler text currently shown at t=0 (from source)'},
    newT0:{type:'array', items:{type:'string'}, description:'proposed atmospheric in-voice nudge lines for t=0 — NO verb/answer/twist'},
    currentHint:{type:'string', description:'current hintText() string (or "none")'},
    newHint:{type:'string', description:'reworked escalated hint shown after struggle — names the exact gesture/control, more specific than newT0'},
    difficultyHint:{type:'string', description:'optional stronger contextual hint for difficultyHintDidShow()'},
    whereToEdit:{type:'string', description:'file + function/approx lines to change; note if any text lives in the SwiftUI HUD rather than the scene'},
    rationale:{type:'string'},
  },
}

const VOICE_SCHEMA = {
  type:'object', additionalProperties:false,
  required:['overall','adjustments'],
  properties:{
    overall:{type:'string', description:'persona-consistency assessment across all 20 drafts'},
    adjustments:{
      type:'array',
      items:{
        type:'object', additionalProperties:false, required:['level','verdict'],
        properties:{
          level:{type:'integer'},
          verdict:{type:'string', enum:['good','too-revealing','too-vague','off-voice']},
          note:{type:'string'},
          revisedNewT0:{type:'array', items:{type:'string'}},
        },
      },
    },
  },
}

function draftPrompt(l){
  return `Rewrite the t=0 clue copy for Glitched Level ${l.idx} (${l.title}) so it stops spoiling the puzzle.

READ the source for the exact current strings + the level's voice context: ${SRC}/${l.file}

THE SECRET (must be DISCOVERED, never stated at t=0): ${l.secret}
WHAT CURRENTLY SPOILS IT AT t=0: ${l.spoiler}
${VOICE}

PRODUCE:
- currentT0: the exact spoiler line(s) you found in source.
- newT0: replacement atmospheric in-voice nudge line(s) that tease without telling (cut the explicit instruction; keep any already-good atmospheric line).
- currentHint / newHint: the escalated stuck-player hint that NOW carries the explicit instruction (name the exact gesture/control). It must be more specific than newT0.
- difficultyHint (optional): a stronger pointed hint for repeated failure.
- whereToEdit: file + function/lines (note if the text is in the SwiftUI HUD, e.g. L1's DRAG DOWN).
Return the schema object.`
}

function voicePrompt(drafts){
  return `You are the VOICE editor for Glitched's de-spoil pass. Below are proposed new t=0 nudges + reworked hints for 20 levels.
${VOICE}
DRAFTS:
${JSON.stringify(drafts, null, 1)}

For EACH level decide: good / too-revealing (still names the answer) / too-vague (player has no idea what category) / off-voice (breaks the corrupted-OS persona). Where not good, give a note and a revisedNewT0. Then give an overall persona-consistency assessment (are these 20 lines one coherent voice?). Return the schema object.`
}

phase('Draft')
const drafts = (await parallel(LEVELS.map(l => () =>
  agent(draftPrompt(l), { label:`draft:L${l.idx} ${l.title}`, phase:'Draft', schema: DRAFT_SCHEMA })
))).filter(Boolean)

phase('VoicePass')
const voice = await agent(voicePrompt(drafts), { label:'voice-consistency', phase:'VoicePass', schema: VOICE_SCHEMA })

log(`DE-SPOIL DRAFTS: ${drafts.length}/20 levels`)
return { drafts: drafts.sort((a,b)=>a.level-b.level), voicePass: voice }
