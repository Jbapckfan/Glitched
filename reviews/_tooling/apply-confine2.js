export const meta = {
  name: 'glitched-confine2',
  description: 'Confine L14 (Focus) + L16 (ShakeUndo) iPad diagonal climbs into centered columns',
  phases: [ { title: 'Confine', detail: 'L14, L16' } ],
}
const S = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched/Scenes'
const FILES = [
  { idx:14, file:'Level14_FocusMode.swift', mech:'Focus/DND freezes orbiting hazards' },
  { idx:16, file:'Level16_ShakeUndo.swift', mech:'shake to rewind 3s' },
]
const SCHEMA = { type:'object', additionalProperties:false, required:['level','summary'], properties:{ level:{type:'integer'}, summary:{type:'string'}, risks:{type:'string'} } }
phase('Confine')
const out = await parallel(FILES.map(f => () =>
  agent(`Fix the iPad VOID on Glitched Level ${f.idx} (${f.mech}).
FILE: ${S}/${f.file}
The iPad composed climb (buildComposedIPadLevel, isWideCanvas-gated) renders as a SHALLOW DIAGONAL (Bit bottom-left, climb up-right with camera-follow), leaving the upper-left empty — the start-frame VOID. Apply the PROVEN CONFINED VERTICAL COLUMN pattern (study ${S}/Level2_Wind.swift and ${S}/Level18_AppSwitcher.swift and ${S}/Level27_VoiceOver.swift buildComposedIPadLevel): author the climb as a zig-zag column centered on size.width/2 whose total horizontal extent fits ~one iPad portrait width, and REMOVE installCameraFollow, so the whole floor->ceiling climb (and its hazards) is visible in one resting frame with no empty band.
RULES: NEVER widen a gap (>130 edge-to-edge) or rise (>85 top-to-top); keep the device mechanic byte-identical; keep the iPhone (non-isWideCanvas) path byte-identical; keep the build green. Study the reference files first, apply with Edit, return the schema object.`,
    { label:`confine2:L${f.idx}`, phase:'Confine', schema: SCHEMA })
))
return { fixes: out.filter(Boolean) }
