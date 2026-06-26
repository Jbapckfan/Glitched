export const meta = {
  name: 'glitched-fix-w01',
  description: 'World 0+1 fixes from the 4-reviewer pass: L4 hardcoded-false, L5 de-spoil, L2/L3 confine iPad climb, L10 center flat course, idle/struggle hint wiring (L0/L9), L7 dup panel',
  phases: [ { title: 'FixW01', detail: 'one agent per scene file' } ],
}

const S = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched/Scenes'

const RULES = `RULES: edit ONLY your file; NEVER widen a gap (>130 edge-to-edge) or rise (>85 top-to-top); keep the iPhone (non-isWideCanvas) path byte-identical when the fix is iPad-only; keep the device mechanic intact; keep the build green (balanced braces). Return a precise summary.`

const FILES = [
  { idx:4, file:'Level4_Volume.swift', label:'L4 isWideCanvas hardcoded false + hint',
    spec:`Line ~76 has \`private var isWideCanvas: Bool { false }\` — dead iPad code (all 4 reviewers flagged it). FLIP to real detection matching siblings: \`private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }\` so the composed iPad branch + camera-follow run. Verify the composed path actually fills the band (it is a flat-ish level — if it has no real climb, instead center it via a uniform vertical lift like Level33's buildFlatLevel + gameplayVerticalLift). ALSO: handleDeath() should call notePlayerStruggle() (it already may); and since this is a no-jump hardware-button puzzle a stuck player may never die — add an IDLE escalation: if there is an update/notePlayerProgress path, trigger showDifficultyHintIfNeeded()-style help after ~15s of no progress (the BaseLevelScene no-progress timer may already cover this — verify it fires here).` },
  { idx:5, file:'Level5_Charging.swift', label:'L5 de-spoil + struggle wiring',
    spec:`Both Claude and Codex flag L5 as SPOILED at t=0: a permanent label literally reads "PLUG IN YOUR CHARGER" with a pulsing empty-battery icon, so the trick is given away. DE-SPOIL it (this level was missed in the de-spoil pass): replace the explicit "PLUG IN YOUR CHARGER" t=0 text with an atmospheric in-voice tease (the dying battery + a vague glitch line, e.g. "I'M... FADING." / "SO COLD. FEED ME.") — keep the pulsing empty-battery icon as the visual nudge. Move the explicit "plug in your charger" instruction into hintText() (the EARNED reveal). ALSO wire notePlayerStruggle() in handleDeath() (Codex: it is missing) so a stuck player escalates. Match the existing GlitchedNarrator voice; keep the charging mechanic + plug-ride untouched.` },
  { idx:2, file:'Level2_Wind.swift', label:'L2 confine iPad climb (void)',
    spec:`Reviewers see iPad VOID: the composed climb either reads as a shallow diagonal or the flat layout shows with empty top two-thirds. Apply the PROVEN confined-column pattern (study ${S}/Level27_VoiceOver.swift / Level15_LowPower.swift buildComposedIPadLevel): make the iPad climb a CONFINED vertical zig-zag column centered on size.width/2 whose total horizontal extent fits ~one iPad portrait width (~1024pt), so the whole floor->ceiling climb is visible in the spawn frame with NO empty upper band. Minimize/remove installCameraFollow. Keep the wind-bridge chasm (235pt, un-jumpable) and every other gap<=130 / rise<=85 byte-identical; iPhone path untouched.` },
  { idx:3, file:'Level3_Static.swift', label:'L3 confine iPad climb + cue',
    spec:`Reviewers see iPad VOID (playfield in bottom ~25%, empty TV-frame interior above). Apply the confined vertical-column pattern (ref Level27/Level15 buildComposedIPadLevel) so the climb fills the band top-to-bottom in one frame. ALSO (Codex/Claude): the inverse-4th-laser cue "THIS ONE LISTENS DIFFERENTLY." placard is too small/easy to miss — bump its font size / make its pulse more noticeable so the inverse rule is discoverable (without naming the answer). Keep the laser mechanic + gaps/rises byte-identical; iPhone path untouched.` },
  { idx:10, file:'Level9_Orientation.swift', label:'L10 (Orientation) center flat iPad course',
    spec:`This is the FREE-DEMO CLOSER (now level 10). Reviewers: iPad portrait wastes the canvas — the flat crusher course sits lower-left, upper half + right third empty. It's a deliberately FLAT level (no tiers — do NOT add platforming or touch the corridor/crusher/rotate gate). Apply a stronger UNIFORM VERTICAL LIFT + decorative upper-band fill (ref Level33's buildFlatLevel + drawIPadUpperBandDecor and Level9's lift): center the flat band vertically and fill the empty upper band with NON-load-bearing structure (crusher bulk extends up, ceiling girders) so it reads filled, not void. Completability byte-identical; iPhone untouched.` },
  { idx:0, file:'Level0_BootSequence.swift', label:'L0 idle-nudge escalation',
    spec:`All reviewers: no stuck-player escalation — the boot scene never calls notePlayerStruggle()/overrides hintText(), so a confused player gets the same looping prompt forever. ADD an idle nudge: ~6s after the main UI (loading bar handle) is revealed with no drag detected, animate the handle with a small wiggle/pulse AND swap/add an explicit hint (e.g. "slide the white dot to the right"). Use a one-shot SKAction timer keyed off the reveal. Do NOT change the boot text, the fake-crash gag, or the drag mechanic.` },
  { idx:9, file:'Level10_TimeTravel.swift', label:'L9 (Time Travel) struggle + pre-hint',
    spec:`This is now level 9 (Time Travel). Codex: handleDeath() does not call notePlayerStruggle(), so failed platforming gives no escalation. ADD notePlayerStruggle() to handleDeath()/the failure path. Claude: tighten the time-to-help — optionally surface a lighter pre-hint at ~12-15s of zero progress (the BaseLevelScene no-progress timer may cover this — verify it fires). Keep the background-the-app mechanic + tree-growth untouched; no t=0 spoiler change needed.` },
  { idx:7, file:'Level7_Screenshot.swift', label:'L7 cut duplicate panel',
    spec:`Claude: two near-identical panels both open with "SOME MOMENTS REFUSE TO MOVE..." (the t=0 discovery panel AND the persistent instruction panel) — redundant, reads like a duplicate-render bug. Keep ONE: prefer the atmospheric discovery line; remove the second panel that repeats the same opening sentence. Codex: the shortest degraded screenshot-freeze (~1.0s) can get tight on late retries — optionally raise the freeze floor slightly (e.g. min 1.5s). Keep the screenshot-freeze mechanic intact.` },
  { idx:8, file:'Level8_DarkMode.swift', label:'L8 OS-toggle discoverability nudge',
    spec:`Claude: the core action (the OS Settings/Control-Center dark-mode switch) is invisible — nothing on screen tells the player it's a SYSTEM toggle, and the in-game TOGGLE DARK MODE fallback button only appears via the accessibility path. ADD a soft discoverability nudge: after ~6-8s of no appearance change, present a one-line GlitchedNarrator hint pointing at the system dark-mode toggle (without over-spoiling — the t=0 "NIGHT AND DAY..." stays). Keep the dark/light platform-swap mechanic untouched.` },
]

const SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','file','summary'],
  properties:{ level:{type:'integer'}, file:{type:'string'}, summary:{type:'string'}, completabilityPreserved:{type:'boolean'}, risks:{type:'string'} },
}

phase('FixW01')
const out = await parallel(FILES.map(f => () =>
  agent(`Fix Glitched ${f.label}.
FILE: ${S}/${f.file}
${RULES}
THE FIX: ${f.spec}
Read the file (and any referenced pattern file), apply with Edit, return the schema object.`,
    { label:`w01:L${f.idx}`, phase:'FixW01', schema: SCHEMA })
))
return { fixes: out.filter(Boolean) }
