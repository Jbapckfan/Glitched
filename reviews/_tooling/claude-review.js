export const meta = {
  name: 'glitched-claude-review',
  description: 'Per-level Claude review (mechanic / completability / iPad layout / clue-hint / fun) of all 34 levels for the side-by-side review console',
  phases: [ { title: 'Review', detail: '34 agents, one per level' } ],
}

const CL = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign'
const SRC = `${CL}/Glitched/Scenes`
const SHOTS = `${CL}/reviews`

// level number -> scene file (post-reorder) + mechanic + objective
const LEVELS = [
  { n:0,  file:'Level0_BootSequence.swift', mech:'Boot / drag', obj:'Drag the stuck 99% loading-bar handle to 100% to boot; fake crash gag.' },
  { n:1,  file:'Level1_Header.swift', mech:'HUD drag', obj:'Drag the LEVEL banner down into the spike pit to form a bridge.' },
  { n:2,  file:'Level2_Wind.swift', mech:'Microphone (blow)', obj:'Blow into the mic to extend a bridge across a chasm.' },
  { n:3,  file:'Level3_Static.swift', mech:'Microphone (noise)', obj:'Noise disables lasers 1-3; the 4th is INVERSE (go silent).' },
  { n:4,  file:'Level4_Volume.swift', mech:'Volume buttons', obj:'Lower volume to keep a wolf asleep + water low.' },
  { n:5,  file:'Level5_Charging.swift', mech:'Charging', obj:'Plug in; ride a rising charging plug up a shaft.' },
  { n:6,  file:'Level6_Brightness.swift', mech:'Brightness', obj:'Raise brightness to reveal platforms; max brightness burns.' },
  { n:7,  file:'Level7_Screenshot.swift', mech:'Screenshot', obj:'Screenshot freezes a flickering ghost bridge to cross.' },
  { n:8,  file:'Level8_DarkMode.swift', mech:'Dark mode', obj:'Toggle dark/light to swap solid platforms; exit needs dark.' },
  { n:9,  file:'Level10_TimeTravel.swift', mech:'App backgrounding', obj:'Background the app ~5s to grow a tree bridge. (Reordered: now level 9.)' },
  { n:10, file:'Level9_Orientation.swift', mech:'Rotation', obj:'Rotate to landscape to widen a corridor past a crusher. (Reordered: now level 10 — the free-demo closer.)' },
  { n:11, file:'Level11_Notification.swift', mech:'Notifications', obj:'Tap the bell, tap the push notification to unlock doors.' },
  { n:12, file:'Level12_Clipboard.swift', mech:'Clipboard', obj:'Copy GLITCH3D to clipboard; terminal reads it.' },
  { n:13, file:'Level13_WiFi.swift', mech:'WiFi toggle', obj:'Toggle WiFi to solidify signal platforms / pass walls.' },
  { n:14, file:'Level14_FocusMode.swift', mech:'Focus / DND', obj:'Enable Focus to freeze orbiting hazards.' },
  { n:15, file:'Level15_LowPower.swift', mech:'Low Power', obj:'Toggle Low Power to swap normal/lunar gravity per section.' },
  { n:16, file:'Level16_ShakeUndo.swift', mech:'Shake undo', obj:'Shake to rewind 3s (limited charges).' },
  { n:17, file:'Level17_AirplaneMode.swift', mech:'Airplane mode', obj:'Enable Airplane Mode to raise platforms to flying positions.' },
  { n:18, file:'Level18_AppSwitcher.swift', mech:'App switcher', obj:'Peek the app switcher to freeze hazards + show trajectories.' },
  { n:19, file:'Level19_FaceID.swift', mech:'Face ID', obj:'Authenticate to open vault doors.' },
  { n:20, file:'Level20_MetaFinale.swift', mech:'Meta finale (W2 boss)', obj:'Walk INTO the corruption wall to trigger a purge.' },
  { n:21, file:'Level23_DeviceName.swift', mech:'Device name', obj:'Name-door opens for you; doppelganger NPC. (Reordered: now W3 opener, level 21.)' },
  { n:22, file:'Level21_VoiceCommand.swift', mech:'Voice', obj:'Say BRIDGE / OPEN / FLY for 3 obstacles. (Reordered: now level 22.)' },
  { n:23, file:'Level22_BatteryPercent.swift', mech:'Battery %', obj:'Real exit hidden below stone 5 at battery<60%; fake exit right. (Reordered: now level 23.)' },
  { n:24, file:'Level24_StorageSpace.swift', mech:'Storage', obj:'Clear cache to dissolve a DATA MASS wall.' },
  { n:25, file:'Level25_TimeOfDay.swift', mech:'Time of day', obj:'Night sleeps enemies; toggle time; secret 3:33.' },
  { n:26, file:'Level26_Locale.swift', mech:'Locale', obj:'Change device language to unscramble signs + swap route.' },
  { n:27, file:'Level27_VoiceOver.swift', mech:'VoiceOver', obj:'Invisible-but-solid bridge platforms; VoiceOver reveals them.' },
  { n:28, file:'Level28_AirDrop.swift', mech:'Share code', obj:'Share a 6-char code, type it back to open the door.' },
  { n:29, file:'Level29_TheLie.swift', mech:'The Lie', obj:'The real exit was behind you at spawn; walk back.' },
  { n:30, file:'Level30_CreditsFinale.swift', mech:'Credits (fake-out)', obj:'Climb the credits; intentional fake ending before W5.' },
  { n:31, file:'Level31_Flashlight.swift', mech:'Flashlight', obj:'Flashlight + tilt to light a dark cave.' },
  { n:32, file:'Level32_MultiTouch.swift', mech:'Multi-touch', obj:'Hold multiple pressure pads at once to open gates.' },
  { n:33, file:'Level33_AppReview.swift', mech:'App review (finale)', obj:'Clear gates; review-prompt padlock auto-breaks after 10s.' },
]

const SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','mechanic','verdict','strengths','concerns','clueHint','suggestion','score'],
  properties:{
    level:{type:'integer'},
    mechanic:{type:'string'},
    verdict:{type:'string', enum:['ship','polish','rework']},
    strengths:{type:'string', description:'what works (1-2 sentences)'},
    concerns:{type:'string', description:'mechanic clarity / completability / iPad layout issues (1-3 sentences)'},
    clueHint:{type:'string', description:'does t=0 avoid spoiling the trick + does a stuck player get escalating help (1-2 sentences)'},
    suggestion:{type:'string', description:'one concrete improvement'},
    score:{type:'integer', description:'overall 1-5 (5=great)'},
  },
}

function prompt(l){
  const nn = String(l.n).padStart(2,'0')
  return `You are writing Claude's review of Glitched Level ${l.n} (${l.mech}) for a side-by-side review console (paired with an independent Codex review).
READ: iPhone ${SHOTS}/iphone/L${nn}.png, iPad ${SHOTS}/ipad/L${nn}.png, and source ${SRC}/${l.file}.
INTENDED DESIGN: ${l.obj}
Give a genuine, critical, specific review covering: (1) mechanic clarity + is the puzzle fair on first encounter; (2) completability / jump-reach (Bit safe gap<=130, rise<=85) + iPad layout (fills the screen, no void/overlap); (3) clue/hint quality — does the t=0 text avoid spoiling the trick AND does a stuck player get escalating help (notePlayerStruggle/hintText); (4) one concrete improvement. Score 1-5. IGNORE the green DEBUG pill + nodes/fps counter. Return the schema object.`
}

phase('Review')
const out = await parallel(LEVELS.map(l => () =>
  agent(prompt(l), { label:`review:L${l.n} ${l.mech}`, phase:'Review', schema: SCHEMA }).then(r => r ? ({...r, _n:l.n, _mech:l.mech}) : null)
))
const reviews = out.filter(Boolean).sort((a,b)=>a._n-b._n)
log(`CLAUDE REVIEWS: ${reviews.length}/34`)
return { reviews }
