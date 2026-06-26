export const meta = {
  name: 'glitched-apply-stage3',
  description: 'Finale restructure (L30 fake-out, completion flag -> L33, L31 subversion) + finale voice routing (L20/L33) + L0 register + L11 occlusion + L30 clip/hint',
  phases: [ { title: 'Finale', detail: 'one agent per file: finale logic + voice + remaining text bugs' } ],
}

const G = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched'

const RULES = `
GLOBAL: edit ONLY your assigned file; do NOT touch geometry/physics/isWideCanvas/completability. Keep the build green (balanced braces). The shared 4th-wall voice is GlitchedNarrator.present(text, in: self, style: .whisper|.alert|.boss) (lower-center safe band). Return a precise edit summary.
`

const FILES = [
  {
    idx:30, file:'Scenes/Level30_CreditsFinale.swift', label:'L30 credits = INTENTIONAL fake-out (not the real end)',
    spec:`The operator wants L30 to be a DELIBERATE fake ending: roll credits as if the game is over, so World 5 (L31-33) can rip it back. Currently it reads as an accidental real finale AND owns the completion flag. CHANGES:
1) COMPLETION FLAG (real bug): find the UserDefaults write that sets 'glitched_game_complete' = true (~line 840) and REMOVE it from L30 (optionally replace with a 'glitched_reached_credits' = true marker). The real game-complete flag will be set in L33 instead. The actual last level must own completion.
2) TEXT CLIP (real bug): the credit rung 'A GLITCHED PRODUCTION' (nameLabel, Menlo-Bold ~10pt) overflows its ~110pt platform and clips to 'GLITCHED PRODUCTIO'. FIX: widen that specific rung to ~150pt (centeredWidth) OR shorten the string to 'GLITCHED PRODUCTION' / drop fontSize to ~8 with preferredMaxLayoutWidth so nothing clips.
3) HINT (real bug): hintText() returns 'Walk across the credits — watch for bugs!' but the level is a vertical CLIMB. Change 'Walk across' -> 'Climb'.
4) STRUGGLE WIRING: handleDeath() (~line 900) never calls notePlayerStruggle() — add it.
5) FAKE-OUT FRAMING (keep the bait, make it land): it is FINE to keep the credits + a 'THANK YOU FOR PLAYING'-style beat as the bait, BUT the top platform currently labeled 'THE FINAL LEVEL' should stay as the bait (the joke is it's NOT). Do NOT add any 'the real end' wording here — L31 supplies the subversion and L33 is the true finale. Keep this level's goodbye lighter/credits-flavored; reserve the definitive sign-off for L33.
6) (Optional voice) if trivial, route the fourth-wall credit asides ("YOU'RE STANDING ON THE PEOPLE WHO MADE ME.", "SAY THANK YOU.") through GlitchedNarrator(.whisper) instead of ad-hoc SKLabelNodes — but do NOT risk the build; skip if it requires restructuring credit-platform text.
Do NOT change the credits CLIMB geometry.`,
  },
  {
    idx:31, file:'Scenes/Level31_Flashlight.swift', label:'L31 = the subversion beat (World 5 begins)',
    spec:`L31 is the FIRST level after the L30 credits fake-out. Add a SUBVERSION narrator beat at level start that retroactively frames L30's credits as a fake-out and announces World 5 (System Override). In configureScene (or a short delayed run after the scene composes), add ONE GlitchedNarrator.present(...) line, style .boss or .alert, lower-center safe band, e.g.: "CREDITS? CUTE. I'M NOT DONE WITH YOU." or "SYSTEM OVERRIDE: ENGAGED. YOU DIDN'T THINK THAT WAS THE END?". Fire it once, early (a ~1-1.5s delay is fine), and DO NOT disturb the flashlight mechanic, the crop-mask, or the t=0 de-spoil clue text already in this file. This is purely an added narrator line.`,
  },
  {
    idx:33, file:'Scenes/Level33_AppReview.swift', label:'L33 = the TRUE finale (owns completion + final sign-off)',
    spec:`L33 is the real last level. CHANGES:
1) COMPLETION FLAG: in the level's end/handleExit sequence (~lines 1333-1428, after the padlock breaks and the player reaches the exit), ADD the UserDefaults write that sets 'glitched_game_complete' = true (the write that was removed from L30). This makes game-completion fire at the actual end.
2) FINAL SIGN-OFF VOICE: the closing monologue ('ONE LAST THING.', 'ALL I ASK...', 'IS ONE LITTLE TAP.', 'SYSTEM OVERRIDE COMPLETE.', 'THANK YOU FOR PLAYING.', 'THE GLITCH REMEMBERS.') is currently rendered via ad-hoc center-screen SKLabelNodes. Route the climactic lines through GlitchedNarrator(.boss) (lower-center safe band) so the campaign's final words use the same voice that opened it. Keep genuinely-diegetic terminal/EXIT UI as-is; only move the fourth-wall monologue lines. Reserve 'THE GLITCH REMEMBERS.' as the final beat.
3) Do NOT change the gate/exit geometry, and do NOT touch the iPad layout — buildFlatLevel / isWideCanvas / gameplayLift / drawIPadUpperBandDecor were already finalized in a prior pass. ONLY add the completion flag (task 1) and route the closing monologue through the narrator (task 2).`,
  },
  {
    idx:20, file:'Scenes/Level20_MetaFinale.swift', label:'L20 W2 boss — route purge threat through narrator',
    spec:`The W2 BOSS purge-threat lines are currently ad-hoc center-screen SKLabelNodes. Route the climactic fourth-wall threat lines (the 'SYSTEM PURGE'/boss-tier taunts, the intro warnings) through GlitchedNarrator with style .boss (lower-center safe band) for voice consistency. Keep genuinely-diegetic terminal text (e.g. 'CORRUPTED', error codes) as bespoke nodes. Do NOT change the de-spoil clue text already applied in Stage 1 (the 'IT WANTS YOU TO TURN BACK...' line + hint), the corruption-wall mechanic, or geometry. Only re-route the existing boss-voice lines through the narrator. If a line is positioned over a specific element for gameplay reasons, leave it. Keep the build green; skip any line whose rerouting would require restructuring.`,
  },
  {
    idx:0, file:'Scenes/Level0_BootSequence.swift', label:'L0 dual-register text bug',
    spec:`Two different copy registers describe the SAME drag-to-boot action on the same screen: an all-caps system line 'DRAG TO 100% TO BOOT' (~line 112) and a lowercase friendly placard 'drag to complete →' (~line 363). Pick ONE register — the uppercase terminal/BIOS voice — and use it for BOTH (e.g. make the placard read 'DRAG TO 100%' or 'DRAG TO COMPLETE' in uppercase Menlo to match the boot log). Purely a copy-consistency fix; do NOT change the boot mechanic, the fake-crash, or geometry.`,
  },
  {
    idx:11, file:'Scenes/Level11_Notification.swift', label:'L11 instruction panel occluded by permission modal',
    spec:`At t=0 the 3-line instruction panel sits at the SAME center position (uiY(size.height/2)) as the cyan 'SYSTEM ACCESS REQUIRED' permission modal, so the clue panel is hidden behind the modal in the opening frame and only reads after 'GOT IT' is tapped (and it auto-fades at 6s, so a slow tapper can miss it). FIX: move the instruction panel OUT from under the centered permission modal — reposition it to the upper band (below the title, clear of the top-right PAUSE) or the lower-center area, AND/OR restart its 6s fade timer when the permission overlay is dismissed so it is fully visible after 'GOT IT'. Do NOT change the notification mechanic or the clue wording (already fine); this is placement/timing only. (notePlayerStruggle was already wired in Stage 1.)`,
  },
]

const SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','summary'],
  properties:{
    level:{type:'integer'},
    summary:{type:'string'},
    completionFlagHandled:{type:'string', description:'for L30/L33: what you did with glitched_game_complete'},
    risks:{type:'string'},
  },
}

function prompt(f){
  return `Apply the finale/voice/text fix for Glitched ${f.label}.
FILE: ${G}/${f.file}
${RULES}
SPEC: ${f.spec}
Read the file, apply with Edit, return the schema object.`
}

phase('Finale')
const out = await parallel(FILES.map(f => () =>
  agent(prompt(f), { label:`finale:L${f.idx}`, phase:'Finale', schema: SCHEMA })
))
const done = out.filter(Boolean)
log(`STAGE 3 FINALE: ${done.length}/${FILES.length} files`)
return { fixes: done }
