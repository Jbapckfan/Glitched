export const meta = {
  name: 'glitched-fix-w01b',
  description: 'W0+1 second pass: L4 confine diagonal->column, L10 fill the right void',
  phases: [ { title: 'FixW01b', detail: 'L4, L10' } ],
}
const S = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched/Scenes'
const RULES = `RULES: edit ONLY your file; NEVER widen a gap (>130) or rise (>85); keep the iPhone (non-isWideCanvas) path byte-identical; keep the device mechanic intact; build green. Return a precise summary.`
const FILES = [
  { idx:4, file:'Level4_Volume.swift', label:'L4 confine the now-active iPad climb to a column',
    spec:`Flipping isWideCanvas activated the composed iPad climb, but it renders as a SHALLOW DIAGONAL (Bit bottom-left, climb up-right) leaving the upper-left empty — the start-frame VOID. Apply the proven CONFINED VERTICAL COLUMN pattern (study ${S}/Level2_Wind.swift and ${S}/Level27_VoiceOver.swift buildComposedIPadLevel): author the climb as a zig-zag column centered on size.width/2 whose total horizontal extent fits ~one iPad portrait width, and REMOVE installCameraFollow, so the whole floor->ceiling climb is visible in one frame with no empty upper-left band. Keep every gap<=130 / rise<=85 and the wolf/volume/water mechanic byte-identical; iPhone path untouched.` },
  { idx:10, file:'Level9_Orientation.swift', label:'L10 (Orientation) fill the right-side void',
    spec:`After the uniform-lift the flat crusher-chase is centered vertically, but the RIGHT ~40% of the iPad frame is still empty grid (the corridor + exit sit left-of-center). This is a FLAT level (do NOT add platforming / touch the corridor/crusher/rotate gate). Fill the canvas better: (a) horizontally CENTER the flat course in the available width (shift it right so it isn't left-biased), AND/OR (b) extend the NON-load-bearing decorative framing across the right side and above (crusher machinery/track, ceiling girders, warning chevrons) so the whole frame reads as an industrial crusher shaft, not empty grid. Completability byte-identical; iPhone untouched. This is the free-demo closer — make it look finished.` },
]
const SCHEMA = { type:'object', additionalProperties:false, required:['level','summary'], properties:{ level:{type:'integer'}, summary:{type:'string'}, risks:{type:'string'} } }
phase('FixW01b')
const out = await parallel(FILES.map(f => () =>
  agent(`Fix Glitched ${f.label}.\nFILE: ${S}/${f.file}\n${RULES}\nTHE FIX: ${f.spec}\nStudy any referenced pattern file first, apply with Edit, return the schema object.`,
    { label:`w01b:L${f.idx}`, phase:'FixW01b', schema: SCHEMA })
))
return { fixes: out.filter(Boolean) }
