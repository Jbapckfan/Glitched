export const meta = {
  name: 'glitched-apply-stage4',
  description: 'Final polish: fix L9/L30/L6 text clip/overlap + L24 iPad diagonal-climb void',
  phases: [ { title: 'Polish', detail: 'L9, L30, L6 text placement + L24 confine climb' } ],
}

const S = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched/Scenes'

const FILES = [
  {
    idx:9, file:'Level9_Orientation.swift', label:'L9 clipped de-spoil sign on iPhone',
    spec:`The new de-spoil tease "THIS HALL WASN'T BUILT FOR YOU." is positioned as a sign near the crusher at the LEFT side, so on the narrow iPhone it is clipped off the left screen edge (only fragments show). The top-center panel "UP IS A MATTER OF OPINION..." renders fine. FIX: make the "THIS HALL WASN'T BUILT FOR YOU." line fully on-screen on iPhone — EITHER reposition that sign so its full width sits within the iPhone safe width (e.g. anchor it on-screen, not at the off-left crusher), OR (cleaner) fold it INTO the existing top-center instruction panel as a second line under "UP IS A MATTER OF OPINION..." and remove the separate clipped sign. Keep it clear of the top-right PAUSE. Do NOT touch geometry/the crusher/rotate mechanic. Verify it reads on BOTH iPhone and iPad.`,
  },
  {
    idx:30, file:'Level30_CreditsFinale.swift', label:'L30 iPhone credit box too narrow',
    spec:`The "GLITCHED PRODUCTION" credit rung's box is too narrow on iPhone — the word is legible but its border cuts through "...TION" (overflows the ~110pt box). The text was already shortened from "A GLITCHED PRODUCTION". FIX the box sizing for this rung: widen that specific credit platform/box toward ~150pt (centeredWidth) so "GLITCHED PRODUCTION" fits, OR drop its nameLabel fontSize to ~8 with preferredMaxLayoutWidth. Do NOT change the credits-climb geometry or other rungs. Verify it fits on iPhone (narrowest) without clipping.`,
  },
  {
    idx:6, file:'Level6_Brightness.swift', label:'L6 iPhone tease overlaps Bit sprite',
    spec:`On the narrow iPhone the new (widened) t=0 tease caption ("I CAN'T SEE EITHER, YOU KNOW." / "THE DARK IS HIDING THE FLOOR FROM BOTH OF US.") overlaps the astronaut sprite / platform art (a z-order collision with the game world, not a HUD panel). FIX: reposition the tease caption so it does not sit on top of Bit's spawn — move it up into the clear upper band (below the title/BRIGHTNESS panel, above the gameplay), or give it a backing plate, so it reads cleanly without covering the character on iPhone. Keep it clear of the top-right PAUSE. Keep the de-spoil text content unchanged; iPad already renders it clean.`,
  },
  {
    idx:24, file:'Level24_StorageSpace.swift', label:'L24 iPad diagonal-climb start-frame void',
    spec:`L24's iPad composed layout is a SHALLOW diagonal camera-follow climb: at spawn the camera rests low-left and the upper ~55% of the frame is empty white (the junk-mass wall, purge terminal and EXIT are up-right along the diagonal, off-screen). It is COMPLETABLE (content scrolls), but it reads as a void. FIX with the proven pattern (see Level27_VoiceOver.swift / Level15_LowPower.swift buildComposedIPadLevel): make the iPad climb a CONFINED vertical/zig-zag column whose total horizontal extent fits within ~one iPad portrait width (~1024pt, columns at size.width/2 ± ~250pt), so the WHOLE climb — including the junk-mass wall, the ↑CLIMB terminal, and the EXIT — is visible top-to-bottom in the spawn frame. Remove/minimize installCameraFollow (a confined column needs no horizontal scroll). Keep every gap<=130 / rise<=85 and the cache-clear-dissolves-the-wall mechanic byte-identical; iPhone path (NOT isWideCanvas) stays unchanged. Study the reference files first.`,
  },
]

const SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','summary'],
  properties:{ level:{type:'integer'}, summary:{type:'string'}, completabilityPreserved:{type:'boolean'}, risks:{type:'string'} },
}

phase('Polish')
const out = await parallel(FILES.map(f => () =>
  agent(`Fix: ${f.label}.
FILE: ${S}/${f.file}
RULES: edit ONLY this file; do NOT widen gaps (>130) or rises (>85) or touch the device mechanic; keep iPhone path byte-identical where the fix is iPad-only; keep build green (balanced braces). Return a precise summary.
THE FIX: ${f.spec}`,
    { label:`polish:L${f.idx}`, phase:'Polish', schema: SCHEMA })
))
return { fixes: out.filter(Boolean) }
