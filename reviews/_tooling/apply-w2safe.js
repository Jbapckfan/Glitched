export const meta = {
  name: 'glitched-fix-w2safe',
  description: 'W2-W5 safe systematic fixes: notePlayerStruggle wiring (L13/19/24/33), L28 force-unwrap crash-hardening, L18 confine iPad climb',
  phases: [ { title: 'Safe', detail: 'hint-net + crash-hardening + one void confine' } ],
}
const S = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched/Scenes'
const R = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/reviews'

const STRUGGLE = ['Level13_WiFi.swift','Level19_FaceID.swift','Level24_StorageSpace.swift','Level33_AppReview.swift']

const SCHEMA = { type:'object', additionalProperties:false, required:['file','summary'], properties:{ file:{type:'string'}, summary:{type:'string'}, risks:{type:'string'} } }

phase('Safe')
const struggle = STRUGGLE.map(f => () =>
  agent(`Wire the stuck-player hint net into Glitched scene ${f}.
FILE: ${S}/${f}
TASK: this scene has a death/failure path (handleDeath() or failLevel()) but never calls notePlayerStruggle(), so repeated failure does not escalate the hint. Add notePlayerStruggle() as the first statement inside handleDeath()/the failure path (after any 'levelState == .playing' guard), matching the pattern used by sibling scenes (e.g. Level4_Volume handleDeath). Do NOT change clue text, geometry, or the device mechanic. Keep the build green. Return the schema object.`,
    { label:`struggle:${f}`, phase:'Safe', schema: SCHEMA }))

const crash = () =>
  agent(`Harden the force-unwrap crash risks in Glitched Level 28 (Share Code).
FILE: ${S}/Level28_AirDrop.swift
CONTEXT: the Kimi review (read it: ${R}/kimi/AirDropScene.md) flags brittle force-unwraps that crash if setup order / key-name parsing drifts (e.g. terminalScreen!, keyboardNode!, keyNode.name!, alphabet.randomElement()!) plus a share-completion handler that ignores completed==false.
TASK: replace the risky force-unwraps with safe handling — use optional binding (guard let / if let), nil-coalescing, or stored non-optional references created at setup — so a nil never crashes the scene. Preserve identical behavior on the happy path. Also handle the cancelled-share case (completed==false) gracefully (don't leave the player stuck with no code/keypad/hint). Do NOT change geometry, the share/decode mechanic, or clue text beyond what's needed. Keep the build green; return the schema object.`,
    { label:'crash:L28', phase:'Safe', schema: SCHEMA })

const confine = () =>
  agent(`Fix the iPad VOID on Glitched Level 18 (App Switcher) — Claude rated it 'rework' for a broken diagonal iPad layout.
FILE: ${S}/Level18_AppSwitcher.swift
The iPad composed climb is a shallow diagonal (camera-follow, Y pinned center) that strands the spawn/instruction in different zones with large dead whitespace. Apply the PROVEN CONFINED VERTICAL COLUMN pattern (study ${S}/Level2_Wind.swift and ${S}/Level27_VoiceOver.swift buildComposedIPadLevel): a zig-zag column centered on size.width/2, total horizontal extent within ~one iPad portrait width, installCameraFollow removed, so the whole floor->ceiling climb + the peek-freeze hazards are visible in one frame with no dead band. Keep every gap<=130 / rise<=85 and the app-switcher peek mechanic byte-identical; iPhone (non-isWideCanvas) path untouched. Return the schema object.`,
    { label:'confine:L18', phase:'Safe', schema: SCHEMA })

const out = await parallel([...struggle, crash, confine])
return { fixes: out.filter(Boolean) }
