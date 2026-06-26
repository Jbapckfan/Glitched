export const meta = {
  name: 'glitched-final-audit',
  description: 'Merge-gate vision audit of all 34 levels (shots3): render OK, HUD overlap, text clipping, iPad void, and de-spoil text renders correctly',
  phases: [ { title: 'FinalCheck', detail: '34 agents, one per level, iPhone+iPad' } ],
}

const SHOTS = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/shots3'

// expect = a short distinctive bit of the NEW de-spoiled t=0 text that SHOULD be on screen
// (to confirm the de-spoil applied + renders un-clipped). geo = level whose iPad layout was changed.
const LEVELS = [
  { idx:0,  expect:'boot log; "DRAG TO 100%" / "DRAG TO COMPLETE" unified uppercase' },
  { idx:1,  expect:'NO "DRAG DOWN" label on the LEVEL 1 banner (removed); whisper may appear lower-center' },
  { idx:2,  expect:'LOOKS WINDY (unchanged)' },
  { idx:3,  expect:'THIS ONE LISTENS DIFFERENTLY (no "INVERSE / QUIET = SAFE")' },
  { idx:4,  expect:'KEEP IT QUIET / IT SLEEPS. THE WATER LISTENS (no "TOO LOUD = FLOOD")' },
  { idx:5,  expect:'unchanged' },
  { idx:6,  expect:"I CAN'T SEE EITHER, YOU KNOW (no \"NOT TOO BRIGHT ~80%\")" },
  { idx:7,  expect:'THE BRIDGE ONLY EXISTS WHEN NOTHING IS LOOKING (no "PRESS SIDE + VOLUME UP")' },
  { idx:8,  expect:"NIGHT AND DAY DON'T AGREE (no \"MOON/SUN PLATFORMS: SOLID\")" },
  { idx:9,  expect:"THIS HALL WASN'T BUILT FOR YOU (no ROTATE/LANDSCAPE)", geo:true },
  { idx:10, expect:'unchanged' },
  { idx:11, expect:'instruction panel NOT hidden under the cyan permission modal' },
  { idx:12, expect:'NO "COPY: GLITCH3D" (password must NOT be shown); tease text instead' },
  { idx:13, expect:'unchanged', geo:true },
  { idx:14, expect:'SO HOW QUIET CAN YOU MAKE YOURSELF (no "ENABLE FOCUS ... FREEZE THE CHAOS")' },
  { idx:15, expect:'THE BATTERY IS DYING (no "TAP POWER")', geo:true },
  { idx:16, expect:'REGRET HAS A GRIP. USE IT (no "SHAKE TO REWIND TIME")' },
  { idx:17, expect:'EVERYTHING TETHERED IS WAITING TO LEAVE (no "TURN ON AIRPLANE MODE")' },
  { idx:18, expect:'SO. STOP WATCHING (no "SWIPE UP TO PEEK & FREEZE TIME")' },
  { idx:19, expect:'unchanged' },
  { idx:20, expect:'IT WANTS YOU TO TURN BACK (no "WALK INTO THE CORRUPTION"); widened panel — check no overlap', geo:false },
  { idx:21, expect:'unchanged' },
  { idx:22, expect:'unchanged' },
  { idx:23, expect:'FIND THE DOOR WITH YOUR NAME (clears PAUSE on iPad)', geo:true },
  { idx:24, expect:'unchanged' },
  { idx:25, expect:"SOMETHING GUARDS THAT LEDGE (no \"TAP CYCLE TIME TO SLEEP\"); widened panel — check no overlap" },
  { idx:26, expect:'THE SIGNS ARE TRYING TO TELL YOU SOMETHING (no "CHANGE YOUR LANGUAGE TO READ"); widened panel', geo:true },
  { idx:27, expect:"THE GAP DOESN'T CARE THAT YOU SEE IT (no \"TOGGLE VOICEOVER\")", geo:true },
  { idx:28, expect:"I CAN'T READ MYSELF IN HERE (no \"SHARE THE TRANSMISSION ... KEY ... BACK IN\")" },
  { idx:29, expect:'unchanged' },
  { idx:30, expect:'credits; "GLITCHED PRODUCTION" NOT clipped to "PRODUCTIO"', geo:false },
  { idx:31, expect:"CAN YOU? (no \"TURN ON YOUR FLASHLIGHT\"); dark cave; .boss subversion line may appear" },
  { idx:32, expect:'CONTACT REQUIRED / ONE OF YOU IS NOT ENOUGH (no "PLACE YOUR FINGERS ON THE NODES")' },
  { idx:33, expect:'THE FINAL LEVEL; flat finale CENTERED on iPad with decorative pillars (not a bottom strip)', geo:true },
]

const SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','render','hudOverlap','textClip','void','despoilOk','severity','summary'],
  properties:{
    level:{type:'integer'},
    render:{type:'string', enum:['ok','blank','crash']},
    hudOverlap:{type:'string', enum:['none','minor','severe']},
    textClip:{type:'string', enum:['none','found'], description:'any clipped/overflowing label text on EITHER device'},
    void:{type:'string', enum:['none','minor','severe'], description:'iPad vertical void (severe = top half empty / bottom strip)'},
    despoilOk:{type:'string', enum:['ok','spoiler-remains','missing','na'], description:'ok=new tease present & old spoiler gone; spoiler-remains=old explicit instruction still shown; na=unchanged level'},
    severity:{type:'string', enum:['clean','polish','blocker']},
    summary:{type:'string'},
  },
}

function prompt(l){
  return `Final merge-gate check of Glitched Level ${l.idx}.
READ both: iPhone ${SHOTS}/iphone/L${String(l.idx).padStart(2,'0')}.png and iPad ${SHOTS}/ipad/L${String(l.idx).padStart(2,'0')}.png
EXPECTED at t=0: ${l.expect}
${l.geo ? 'This level had an iPad-LAYOUT fix — verify the iPad frame fills the vertical band (no severe top-empty / bottom-strip void).' : ''}
IGNORE the green "DEBUG" pill (top-left) and "nodes/fps" counter (bottom-right) — Debug-only, never flag.
CHECK:
- render: did BOTH devices compose (not all-black/blank)?
- hudOverlap: any instruction panel/title/control overlapping the top-right PAUSE button or running off a screen edge, EITHER device? (Several panels were widened for new text — look carefully.)
- textClip: any label text clipped/overflowing its box/edge, EITHER device?
- void: iPad vertical void? (none unless severe top-empty/bottom-strip)
- despoilOk: is the NEW tease text present and the OLD explicit instruction GONE? (If "expect: unchanged", set na.) Flag spoiler-remains if the old answer text still shows.
- severity: blocker (crash, severe void, password/spoiler still shown, text clipped badly) / polish / clean.
Return the schema object.`
}

phase('FinalCheck')
const out = await parallel(LEVELS.map(l => () =>
  agent(prompt(l), { label:`final:L${l.idx}`, phase:'FinalCheck', schema: SCHEMA })
))
const r = out.filter(Boolean)
const blockers = r.filter(x => x.severity === 'blocker')
const polish = r.filter(x => x.severity === 'polish')
const spoilerRemains = r.filter(x => x.despoilOk === 'spoiler-remains')
const clips = r.filter(x => x.textClip === 'found')
const overlaps = r.filter(x => x.hudOverlap !== 'none')
const voids = r.filter(x => x.void === 'severe')
const renderBad = r.filter(x => x.render !== 'ok')
log(`FINAL AUDIT: ${blockers.length} blockers, ${polish.length} polish, ${spoilerRemains.length} spoiler-remains, ${clips.length} clips, ${overlaps.length} overlaps, ${voids.length} severe-void, ${renderBad.length} render-bad`)
return {
  blockers: blockers.map(x=>({level:x.level, summary:x.summary})),
  spoilerRemains: spoilerRemains.map(x=>({level:x.level, summary:x.summary})),
  clips: clips.map(x=>({level:x.level, summary:x.summary})),
  overlaps: overlaps.map(x=>({level:x.level, sev:x.hudOverlap, summary:x.summary})),
  severeVoids: voids.map(x=>({level:x.level, summary:x.summary})),
  renderBad: renderBad.map(x=>({level:x.level, render:x.render, summary:x.summary})),
  polish: polish.map(x=>({level:x.level, summary:x.summary})),
  allClean: blockers.length===0 && renderBad.length===0 && spoilerRemains.length===0,
}
