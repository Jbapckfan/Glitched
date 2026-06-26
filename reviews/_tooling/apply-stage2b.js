export const meta = {
  name: 'glitched-apply-stage2b',
  description: 'Second geometry pass: L15 (confine climb to one viewport like L23/L27) + L33 (uniform-lift the flat finale like L9) — kill the residual iPad void',
  phases: [ { title: 'Geometry2', detail: 'L15 confined climb, L33 centered flat finale' } ],
}

const S = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched/Scenes'

const RULES = `
HARD CONSTRAINTS: NEVER widen a gap (>130 edge-to-edge) or rise (>85 top-to-top). iPhone path (NOT isWideCanvas) stays BYTE-IDENTICAL. Build stays green. Edit ONLY the iPad/isWideCanvas branch. Return a precise summary.
`

const FILES = [
  {
    idx:15, file:'Level15_LowPower.swift', label:'L15 — confine the climb to one viewport (no wide camera scroll)',
    ref:`${S}/Level27_VoiceOver.swift and ${S}/Level23_DeviceName.swift (study how their buildComposedIPadLevel make a TALL climb that fits within ~one iPad portrait width and is fully visible top-to-bottom at spawn — a narrow zig-zag column centered on size.width/2, little/no horizontal installCameraFollow)`,
    spec:`L15's iPad climb still spreads WIDE horizontally with installCameraFollow, so at spawn the camera sits low-left and the upper half of the frame is empty dead-sky (the high tiers are off-screen RIGHT, not visible above). FIX: rework buildComposedIPadLevel to a CONFINED VERTICAL zig-zag column — like Level27/Level23 — whose total horizontal extent fits within ~one iPad portrait width (~1024pt, e.g. columns at size.width/2 ± ~250pt), so the ENTIRE floor->ceiling climb is visible in the spawn frame with NO empty upper band. Remove or minimize installCameraFollow (a confined column needs no horizontal scroll; if any pan remains, clamp it so the resting frame centers the column). Keep the 4 gravity-section beats (normal/lunar) as vertical tiers via verticalTier(idx, of:nTiers) with per-tier rise <=85 and edge-to-edge gaps <=130 — completability byte-identical, never widen. The narrow-drop (needs normal gravity) and wide-chasm (needs lunar) gates must keep their exact relative geometry; just lay them out vertically within the confined width. Study the reference files first.`,
  },
  {
    idx:33, file:'Level33_AppReview.swift', label:'L33 — center the FLAT finale (it is NOT a climb)',
    ref:`${S}/Level9_Orientation.swift (study its iPad UNIFORM VERTICAL LIFT: a flat, no-climb course centered in the iPad band by shifting every gameplay Y by the same delta, completability byte-identical)`,
    spec:`L33 is a deliberately FLAT finale ("JUST GET TO THE EXIT" — two gates + a locked exit on one ground line; the joke is the review-prompt). It must NOT become a vertical climb. Right now its composed iPad path still bottom-anchors the flat course, leaving a huge empty band above. FIX like Level9: apply a UNIFORM VERTICAL LIFT so the whole flat course band (ground + gates + exit + Bit spawn + the review padlock) sits centered in the iPad canvas — capture the band's current bottom/top, compute a single lift that biases it slightly above center, and add that SAME delta to every gameplay Y (so the walk + the 10s padlock + gate spacing are byte-identical). Optionally fill the upper band with NON-load-bearing decorative structure (the gate pillars/girders extend upward, ceiling framing) so the canvas reads filled rather than empty. Keep gaps/geometry/the padlock-auto-break exactly. Do NOT add platforming. Study Level9's lift approach first. (Stage 2 already set isWideCanvas to real detection — keep that; just make the composed/flat layout center instead of bottom-hug. If the composed path is overcomplicating a flat level, it is fine to route iPad through a centered version of the flat layout.)`,
  },
]

const SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','summary','completabilityPreserved'],
  properties:{ level:{type:'integer'}, summary:{type:'string'}, completabilityPreserved:{type:'boolean'}, risks:{type:'string'} },
}

phase('Geometry2')
const out = await parallel(FILES.map(f => () =>
  agent(`Fix the residual iPad void: ${f.label}.
FILE: ${S}/${f.file}
REFERENCE (study first, as the proven pattern): ${f.ref}
${RULES}
THE FIX: ${f.spec}
Read the reference + your file, apply with Edit, return the schema object.`,
    { label:`geo2:L${f.idx}`, phase:'Geometry2', schema: SCHEMA })
))
return { fixes: out.filter(Boolean) }
