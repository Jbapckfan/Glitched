export const meta = {
  name: 'glitched-apply-stage2',
  description: 'Apply iPad-layout geometry fixes (4 void blockers + L9 + L23 overlap) to Glitched — redistribute tiers / compress horizontal spread, NEVER widen a gap',
  phases: [ { title: 'Geometry', detail: 'one agent per level, iPad-layout fix only' } ],
}

const SRC = '/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign/Glitched/Scenes'

const RULES = `
HARD CONSTRAINTS (the redesign's load-bearing rules):
- NEVER widen a gap or rise. Bit's reach is FIXED: safe edge-to-edge gap <= 130 (hard 145), safe top-to-top rise <= 85 (hard 91). Completability must stay byte-identical.
- The iPhone path (NOT isWideCanvas) must stay BYTE-IDENTICAL — only touch the iPad / isWideCanvas / buildComposedIPadLevel branch.
- Shared helpers on BaseLevelScene: playableGroundY(iphoneGround:) (iPad floor near bottom), playableCeilingY() (just under title/HUD ~ topSafeY-150), playableBandHeight, verticalTier(i, of:count, iphoneGround:) (per-tier rise auto-clamped to <=85), fillTierCount(iphoneGround:, max:) (tier budget to reach the ceiling), installCameraFollow(worldWidth:playerController:) (HORIZONTAL pan only; camera Y stays scene-centered).
- The GOAL: on a tall iPad portrait canvas the composed course must FILL the vertical band floor->ceiling, not hug the bottom and not spread so far horizontally that each viewport slice is mostly empty sky.
- Build must stay green. Return a precise summary + the new tier count / world width you chose.
`

const LEVELS = [
  {
    idx:33, file:'Level33_AppReview.swift', label:'L33 isWideCanvas hardcoded false',
    fix:`Line ~62 hardcodes \`private var isWideCanvas: Bool { false }\`, so iPad wrongly runs buildPhoneLevel (thin centered strip). The full buildComposedIPadLevel already exists. FIX: replace the constant with real detection — \`private var isWideCanvas: Bool { size.height > 1000 && size.width >= designWidth }\` (designWidth=820 is already defined in this file). That routes iPad through the existing composed climb (raises floor, builds up via verticalTier, installs camera follow). No other change. Verify the composed path's tierCount actually reaches the ceiling (e.g. max(6, ceil(playableBandHeight/maxJumpableRise)+1)).`,
  },
  {
    idx:15, file:'Level15_LowPower.swift', label:'L15 climb compressed to bottom 24%',
    fix:`In buildComposedIPadLevel the climb occupies only the bottom ~24% (56% dead sky); the finale shelf that should cap near playableCeilingY renders at ~73% down, so playableCeilingY/tier budget is too low. FIX: (1) ensure the ceiling anchor uses playableCeilingY() (near top safe area) — the shelf is currently set well below it. (2) raise the tier budget: nTiers is currently min(fillTierCount, 12) — remove or raise that 12 cap so the staircase reaches the ceiling at <=85 per-tier rise (use fillTierCount(iphoneGround:) directly, optionally capped higher e.g. 16). (3) ensure groundY = playableGroundY sits near the bottom and the finale/float-shelf sits near playableCeilingY, with tiers distributed across the FULL floor->ceiling span. Do NOT widen any gap/rise — only redistribute tiers vertically to fill the ~56% dead sky.`,
  },
  {
    idx:26, file:'Level26_Locale.swift', label:'L26 over-widened horizontally (~3000pt)',
    fix:`The hidden REVEAL staircase advances ~150-200pt rightward per single-tier rise across a ~3000pt-wide camera world, so each ~1032pt viewport slice shows only low tiers under a vast empty sky (~46% dead), and the exit is scrolled off-right. FIX: make the VERTICAL axis dominant — shrink the per-step horizontal advance of the staircase (cut the inter-stair X gaps toward the minimum, trim stair widths) so a single ~1032pt viewport spans playableGroundY..playableCeilingY; reduce composedWorldWidth so the course is at most ~1.3-1.5x the viewport (not ~3x). Keep gaps<=130 / rises<=85 (do NOT widen). Anchor the wend PEAK and the exit door at an X within (or just past) the spawn-camera window so the launch frame shows floor-to-ceiling content, not a bottom strip.`,
  },
  {
    idx:27, file:'Level27_VoiceOver.swift', label:'L27 side-scroller strands gameplay bottom-left',
    fix:`buildComposedIPadLevel authors a ~1732pt-wide horizontally-scrolling DIAGONAL (x 70->1630 maps to tier 0->13) + installCameraFollow, so the portrait-iPad camera rests at the low-left spawn and the frame shows Bit in the corner under blank dead-sky; the high tiers are off-screen RIGHT, never stacked above. FIX: replace the horizontal side-scroller with a TRUE vertical fill that fits the iPad width — stack the same ~13 stones UPWARD as a narrow zig-zag COLUMN whose total horizontal extent is <= ~900pt (alternating left/right around screen center as it climbs), so little/no horizontal camera-follow is needed. Keep tierCount=14 / verticalTier(idx, of:14) (~83pt rises) and the +1-tier-per-stone climb (rises stay <=85); keep consecutive edge-to-edge horizontal gaps in the 40-80pt band. Then REST t5, BREATH t10, finale t12, exit t13 are all visible above the bottom-left spawn in one resting frame. If you keep a short camera-follow, clamp it so the resting frame centers on the climb column, not the corner. Leave buildPhoneLevel untouched.`,
  },
  {
    idx:9, file:'Level9_Orientation.swift', label:'L9 flat crusher, top 60-70% empty (polish)',
    fix:`L9 is a deliberately FLAT single-floor crusher-chase (no jumps/tiers — do NOT add platforming or change the corridor/crusher/rotate gate). On iPad the floor is pinned to the bottom ~22-25% leaving the upper ~60-70% as empty dead-sky. FIX (cosmetic fill only, completability untouched): (a) lift the whole flat course band toward vertical-center using the uniform-shift approach (raise the iPad ground anchor so the floor + corridor + exit sit around mid-screen, every gameplay Y shifted by the SAME delta so the walk is byte-identical), AND/OR (b) fill the upper band with NON-load-bearing background structure (e.g. the crusher's bulk/teeth extend upward, ceiling girders, hazard framing) so the canvas doesn't read as empty sky. Keep the rotate->corridorGap(18->100) + crusher-disarm gate exactly. This is the lowest-risk of the set — prefer a uniform vertical lift + decorative upper fill over any layout restructure.`,
  },
  {
    idx:23, file:'Level23_DeviceName.swift', label:'L23 minor HUD overlap',
    fix:`Minor HUD overlap flagged on iPad (a panel/control near the top-right PAUSE button, or a label running close to a screen edge). FIX: nudge the offending instruction panel / control so it clears the top-right PAUSE reserved zone (~88x88 at the trailing safe area) and stays inboard of the screen edges on iPad. Text/clue content and the device mechanic stay unchanged. (The name-door doppelganger geometry is fine — completability OK — touch only the HUD placement.)`,
  },
]

const GEO_SCHEMA = {
  type:'object', additionalProperties:false,
  required:['level','summary','completabilityPreserved'],
  properties:{
    level:{type:'integer'},
    summary:{type:'string', description:'precise edits made'},
    newTierCount:{type:'string', description:'tier count / world width chosen (if applicable)'},
    completabilityPreserved:{type:'boolean', description:'confirm no gap>145 / rise>91 introduced and iPhone path untouched'},
    risks:{type:'string'},
  },
}

function geoPrompt(l){
  return `Fix the iPad layout for Glitched ${l.label}.
FILE: ${SRC}/${l.file}
${RULES}
THE FIX: ${l.fix}
Read the file's buildComposedIPadLevel / isWideCanvas region, apply the fix with Edit, and return the schema object. Double-check braces balance and that you touched ONLY the iPad path.`
}

phase('Geometry')
const fixes = await parallel(LEVELS.map(l => () =>
  agent(geoPrompt(l), { label:`geo:L${l.idx}`, phase:'Geometry', schema: GEO_SCHEMA })
))
const done = fixes.filter(Boolean)
log(`STAGE 2 GEOMETRY: ${done.length}/${LEVELS.length} levels fixed`)
return { fixes: done, completabilityFlags: done.filter(f => !f.completabilityPreserved).map(f => f.level) }
