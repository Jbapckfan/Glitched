import SpriteKit
import UIKit

/// Level 31: Flashlight
/// A dark cave level where the player must turn on their phone's flashlight
/// and physically tilt the device to aim a light cone through the darkness.
/// Holding the phone vertical illuminates far ahead; flat illuminates the floor.
/// The player must alternate between viewing angles to navigate stalactites
/// hanging from the ceiling and invisible pit traps in the floor.
final class FlashlightScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style (Inverted — white lines on dark)
    private let fillColor = SKColor(white: 0.06, alpha: 1.0)
    private let strokeColor = SKColor.white
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Extended level for horizontal scrolling
    private let levelWidth: CGFloat = 3200

    // Flashlight state
    private var isFlashlightOn = false
    private var currentPitch: Double = 0.0  // radians, -pi/2 = vertical, 0 = flat

    /// System-level Reduce Motion (Settings > Accessibility > Motion). When on we
    /// skip the purely cosmetic instruction-panel pulse, exit-portal pulse,
    /// exit-glow pulse, and exit down-arrow bob. NONE of these are load-bearing:
    /// the level's hazards (stalactites, pits, death zone) and the exit trigger are
    /// unaffected — the door and its glow stay drawn at a steady, legible alpha.
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    // Light cone (SKCropNode system)
    private var cropNode: SKCropNode!
    private var levelContainer: SKNode!
    private var lightMask: SKShapeNode!

    // Smoothed light dimensions for interpolation
    private var currentLightWidth: CGFloat = 60.0
    private var currentLightHeight: CGFloat = 60.0
    private var currentLightOffsetY: CGFloat = 0.0
    private var currentLightOffsetX: CGFloat = 0.0

    // Ambient glow that always shows around player
    private var ambientGlow: SKShapeNode!

    // Cave decoration containers
    private var stalactiteNodes: [SKNode] = []
    private var floorTrapMarkers: [SKNode] = []
    private var caveCreatures: [SKNode] = []

    // Instruction panel
    private var instructionPanel: SKNode?

    // Fourth-wall commentary tracking
    private var flashlightOnCommentShown = false
    private var verticalCommentShown = false
    private var exitCommentShown = false

    // Section checkpoints (x positions) for progress tracking.
    // RESPAWN-IN-GAP FIX: checkpoint[3] was 2600 — Section 4 ends at 2560 and the
    // Section 5 exit platform doesn't begin until 2650, so x=2600 sits over the
    // open death gap. checkSectionProgress drives spawnPoint off these x values, so
    // respawning at the last checkpoint dropped Bit straight into the pit (instant
    // re-death loop). Move it to 2700, which lands over the wide exit platform
    // (createPlatform at x:2850, width 400 -> spans 2650...3050), giving a safe
    // respawn footing on every device width.
    private let sectionCheckpoints: [CGFloat] = [400, 1000, 1800, 2700]
    private var lastCheckpointReached = -1

    // Exit door references
    private var exitDoorFrame: SKShapeNode?
    private var exitDoorPortal: SKShapeNode?

    // Death zone y position
    private let deathZoneY: CGFloat = -100

    // MARK: - Native-iPad vertical fill (Phase 0)
    //
    // L31 is ALREADY a worldWidth (3200) camera-follow course, so it fills the iPad
    // horizontally via the bespoke updateCamera below — no installCameraFollow needed
    // (that would double-register a camera tick). The gap was VERTICAL: the cave's
    // gameplay was pinned to a single low floor (groundY 160) while the tall iPad
    // canvas above stayed dark and EMPTY — the dark cave read as "broken", not
    // deliberate. The fix is a NEW iPad-only route (buildComposedIPadLevel) that
    // CLIMBS through the full usable band using the shared verticalTier helper: a low
    // spawn on tier 0 rises through staged stalactite + pit-trap beats to the signature
    // finale (exit door) on the TOP tier near the ceiling, so the cave reads
    // top-to-bottom. Faint silhouette hints (ledges, hanging stalactites, a far wall)
    // are drawn across the full height so the darkness is clearly intentional.
    //
    // iPhone is untouched: isWideCanvas is false on phones, so buildLevel() routes to
    // the original section builders verbatim, groundY returns 160, and spawn/checkpoint
    // Y stays 220. The iPad path is fully gated behind isWideCanvas. The flashlight +
    // tilt + bespoke camera mechanic, the fallback (always-on ambient glow + exit
    // glow), spawn/exit reachability, and the stalactite apex-clearance / pit-spacing
    // trap geometry are all preserved.
    private var groundY: CGFloat { playableGroundY(iphoneGround: 160) }

    /// True only on iPad-class canvases. Gates the NEW composed vertical-climb layout
    /// so iPhone output stays byte-identical (mirrors L29's isWideCanvas convention).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 800 }

    /// Spawn / respawn footing, ground-relative (160 + 60 = 220 on iPhone, so
    /// byte-identical). Used as the iPhone spawn/checkpoint Y; the iPad path tracks a
    /// per-checkpoint Y instead (see ipadCheckpoints) because its route is tiered.
    private var spawnY: CGFloat { groundY + 60 }

    /// iPad-only checkpoint (x, respawnY) pairs, populated by buildComposedIPadLevel so
    /// a respawn after the climb begins lands ON the tier the player had reached rather
    /// than back at the floor (or in a gap). Empty on iPhone (which uses the original
    /// x-only sectionCheckpoints at y=220).
    private var ipadCheckpoints: [(x: CGFloat, y: CGFloat)] = []

    /// Number of tiers the iPad climb uses. Chosen so the band/(count-1) per-tier rise
    /// stays at or under the safe jump (verticalTier also clamps to maxJumpableRise),
    /// AND so the TOP tier reaches the ceiling — i.e. the route spans the FULL height.
    /// With the rise clamped at 85, a tall iPad band needs ~13 single-jump steps to
    /// climb floor->ceiling, so count scales with the band rather than a fixed small N.
    private var ipadTierCount: Int {
        let band = playableBandHeight(iphoneGround: 160)
        let needed = Int(ceil(band / BaseLevelScene.maxJumpableRise)) + 1
        return max(4, min(needed, 16))   // 4..16 tiers; top tier reaches the ceiling
    }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world5, index: 31)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.flashlight])
        DeviceManagerCoordinator.shared.configure(for: [.flashlight])

        setupBackgroundAtmosphere(mood: .tense)
        setupCropNodeSystem()
        buildCaveBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
        setupAmbientGlow()
    }

    // MARK: - Crop Node Light System

    /// The core visual trick: all level content lives inside an SKCropNode
    /// whose mask is an ellipse representing the flashlight beam.
    /// When the flashlight is off, only a tiny circle around the player is visible.
    private func setupCropNodeSystem() {
        // Container holds all gameplay nodes (platforms, hazards, exit, decorations)
        levelContainer = SKNode()
        levelContainer.zPosition = 10

        // Crop node clips the container to the light mask shape
        cropNode = SKCropNode()
        cropNode.zPosition = 10
        cropNode.addChild(levelContainer)

        // Initial mask — tiny circle (flashlight off)
        lightMask = SKShapeNode(ellipseOf: CGSize(width: 60, height: 60))
        lightMask.fillColor = .white
        lightMask.strokeColor = .clear
        cropNode.maskNode = lightMask

        addChild(cropNode)
    }

    // MARK: - Cave Background (drawn outside crop node so it's always visible but very dark)

    private func buildCaveBackground() {
        // The cave background is a very dark layer drawn outside the crop node
        // so you can always faintly see the cave walls even without light.
        let bgContainer = SKNode()
        bgContainer.zPosition = -100
        addChild(bgContainer)

        // Cave ceiling line — a long irregular path across the top
        let ceilingPath = CGMutablePath()
        ceilingPath.move(to: CGPoint(x: -50, y: topSafeY - 10))
        var x: CGFloat = 0
        while x <= levelWidth + 50 {
            let y = size.height - 40 + CGFloat.random(in: -15...15)
            ceilingPath.addLine(to: CGPoint(x: x, y: y))
            x += CGFloat.random(in: 30...80)
        }
        let ceiling = SKShapeNode(path: ceilingPath)
        ceiling.strokeColor = strokeColor.withAlphaComponent(0.08)
        ceiling.lineWidth = lineWidth
        ceiling.fillColor = .clear
        bgContainer.addChild(ceiling)

        // Cave floor line. Drawn 40pt below the gameplay floor (groundY) so on iPad
        // the faint cave-floor silhouette tracks the lifted ground instead of sitting
        // far below it. On iPhone groundY is 160 -> base 120, byte-identical to the
        // prior literal.
        let caveFloorBaseY = groundY - 40
        let floorPath = CGMutablePath()
        floorPath.move(to: CGPoint(x: -50, y: caveFloorBaseY))
        x = 0
        while x <= levelWidth + 50 {
            let y: CGFloat = caveFloorBaseY + CGFloat.random(in: -10...10)
            floorPath.addLine(to: CGPoint(x: x, y: y))
            x += CGFloat.random(in: 30...80)
        }
        let floor = SKShapeNode(path: floorPath)
        floor.strokeColor = strokeColor.withAlphaComponent(0.06)
        floor.lineWidth = lineWidth
        floor.fillColor = .clear
        bgContainer.addChild(floor)

        // ANALYSIS NOTE — "dark cave reads empty/broken": on iPad the gameplay now
        // climbs the full height, but the BACKGROUND must also read as a deliberate
        // tall cave (not a void) at every elevation. Add faint silhouette hints across
        // the whole band: a far back-wall seam, a few mid-air hanging-rock ghosts, and
        // sparse ledge ticks at the tier elevations. Drawn outside the crop node at
        // very low alpha so they sit under the flashlight beam — present enough to say
        // "the dark is on purpose", invisible enough to keep the reveal mechanic.
        // iPhone-gated: skipped on phone so phone output is byte-identical.
        if isWideCanvas {
            buildCaveSilhouetteHints(in: bgContainer)
        }

        // Faint vertical crack lines in the background
        for i in 0..<20 {
            let crackX = CGFloat(i) * (levelWidth / 20) + CGFloat.random(in: -40...40)
            let crackPath = CGMutablePath()
            let startY = size.height - CGFloat.random(in: 40...120)
            let endY = CGFloat.random(in: 100...200)
            crackPath.move(to: CGPoint(x: crackX, y: startY))
            var cy = startY
            while cy > endY {
                cy -= CGFloat.random(in: 15...40)
                let dx = CGFloat.random(in: -8...8)
                crackPath.addLine(to: CGPoint(x: crackX + dx, y: cy))
            }
            let crack = SKShapeNode(path: crackPath)
            crack.strokeColor = strokeColor.withAlphaComponent(0.04)
            crack.lineWidth = 1.0
            bgContainer.addChild(crack)
        }
    }

    // MARK: - Cave Silhouette Hints (iPad-only, full-height "deliberate darkness")

    /// Faint, always-dark background silhouettes spanning the full usable band so the
    /// tall iPad cave reads as an intentional dark space, not an empty/broken void.
    /// Everything here is purely cosmetic (no physics, no contact), drawn at very low
    /// alpha OUTSIDE the crop node so it never competes with the flashlight reveal.
    /// Authored at absolute scene coordinates across the full 3200 width and from the
    /// gameplay floor up to just under the title, so the silhouette tracks the climbing
    /// route. iPad-gated by the caller; never runs on iPhone.
    private func buildCaveSilhouetteHints(in bg: SKNode) {
        let floorY = groundY
        let ceilingY = playableCeilingY()
        let band = max(120, ceilingY - floorY)

        // 1) A far back-wall seam: a single soft vertical-ish ridge line running the
        //    full height at a few x stations, so the eye reads depth at every elevation.
        let seamStations: [CGFloat] = stride(from: 220, through: levelWidth - 200, by: 360).map { $0 }
        for sx in seamStations {
            let seam = CGMutablePath()
            seam.move(to: CGPoint(x: sx, y: floorY - 30))
            var sy = floorY - 30
            while sy < ceilingY {
                sy += CGFloat.random(in: 40...70)
                seam.addLine(to: CGPoint(x: sx + CGFloat.random(in: -14...14), y: min(sy, ceilingY)))
            }
            let seamNode = SKShapeNode(path: seam)
            seamNode.strokeColor = strokeColor.withAlphaComponent(0.035)
            seamNode.lineWidth = 1.5
            seamNode.fillColor = .clear
            seamNode.zPosition = -90
            bg.addChild(seamNode)
        }

        // 2) Mid-air hanging-rock ghosts: faint stalactite silhouettes at varied mid
        //    heights so the upper half is never blank. Spread across the width.
        for i in 0..<14 {
            let gx = 260 + CGFloat(i) * (levelWidth - 460) / 13 + CGFloat.random(in: -30...30)
            // Stagger the suspended tip across the band (avoid the floor/ceiling edges).
            let tipY = floorY + band * CGFloat.random(in: 0.30...0.92)
            let len = CGFloat.random(in: 30...64)
            let w = CGFloat.random(in: 10...20)
            let ghost = CGMutablePath()
            ghost.move(to: CGPoint(x: gx - w / 2, y: tipY + len))
            ghost.addLine(to: CGPoint(x: gx, y: tipY))
            ghost.addLine(to: CGPoint(x: gx + w / 2, y: tipY + len))
            let ghostNode = SKShapeNode(path: ghost)
            ghostNode.strokeColor = strokeColor.withAlphaComponent(0.05)
            ghostNode.lineWidth = 1.2
            ghostNode.fillColor = fillColor.withAlphaComponent(0.4)
            ghostNode.zPosition = -88
            bg.addChild(ghostNode)
        }

        // 3) Ledge ticks at the climbing tier elevations: short horizontal dashes that
        //    hint "there is footing up here", scattered along the route so the player
        //    senses the staircase even before the beam finds it.
        let tierCount = ipadTierCount
        for tier in 1..<tierCount {
            let ty = verticalTier(tier, of: tierCount, iphoneGround: 160)
            guard ty < ceilingY else { continue }
            let ticks = 3 + (tier % 3)
            for _ in 0..<ticks {
                let tx = 300 + CGFloat.random(in: 0...(levelWidth - 600))
                let tickPath = CGMutablePath()
                let halfW = CGFloat.random(in: 14...34)
                tickPath.move(to: CGPoint(x: tx - halfW, y: ty + CGFloat.random(in: -6...6)))
                tickPath.addLine(to: CGPoint(x: tx + halfW, y: ty + CGFloat.random(in: -6...6)))
                let tick = SKShapeNode(path: tickPath)
                tick.strokeColor = strokeColor.withAlphaComponent(0.04)
                tick.lineWidth = 1.0
                tick.zPosition = -89
                bg.addChild(tick)
            }
        }
    }

    // MARK: - Level Title

    private func setupLevelTitle() {
        // Title lives in the crop node so it's only visible in light
        let title = SKLabelNode(text: "LEVEL 31")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        levelContainer.addChild(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        levelContainer.addChild(underline)

        let subtitle = SKLabelNode(text: "FLASHLIGHT")
        subtitle.fontName = "Menlo"
        subtitle.fontSize = 10
        subtitle.fontColor = strokeColor
        subtitle.alpha = 0.6
        subtitle.position = CGPoint(x: 80, y: topSafeY - 52)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        levelContainer.addChild(subtitle)
    }

    // MARK: - Level Building

    // L3 pattern dispatcher: iPhone keeps its exact historic flat-cave layout
    // (buildPhoneSections, byte-identical); iPad gets a NEW hand-composed VERTICAL
    // climb that spans the full height. The signature flashlight mechanic, exit
    // door, and death zone are shared scaffolding on both paths.
    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneSections()
        }

        // === Global death zone (shared) ===
        buildDeathZone()
    }

    // MARK: - iPhone path (byte-identical to the original flat-cave layout)
    //
    // groundY is the member that returns 160 on iPhone-class canvases, so every
    // platform/hazard Y below is unchanged from the original hard-coded layout.
    private func buildPhoneSections() {
        let groundY = self.groundY

        // === SECTION 1: Start alcove (x: 0 - 400) ===
        buildStartSection(groundY: groundY)

        // === SECTION 2: Stalactite gauntlet (x: 400 - 1000) ===
        buildStalactiteGauntlet(groundY: groundY)

        // === SECTION 3: Floor trap section (x: 1000 - 1800) ===
        buildFloorTrapSection(groundY: groundY)

        // === SECTION 4: Mixed section (x: 1800 - 2600) ===
        buildMixedSection(groundY: groundY)

        // === SECTION 5: Exit area (x: 2600 - 3200) ===
        buildExitSection(groundY: groundY)
    }

    // MARK: - iPad path (NEW hand-composed full-height vertical climb)
    //
    // Model: L30 — a true vertical climb that fills top-to-bottom. The same cave
    // language (continuous footing -> stalactite gauntlet -> pit-trap floor -> mixed
    // tension -> exit) is re-staged as a STAIRCASE climbing across the full 3200-wide
    // camera-follow course, rising from a low tier-0 spawn to the exit door on the TOP
    // tier near the ceiling. Geometry is NEVER scaled: every step uses verticalTier
    // (per-tier rise auto-clamped to maxJumpableRise=85) and every horizontal gap is
    // bounded <= maxJumpableGap=130. Heights vary tier-to-tier (the route dips and
    // climbs, it is not a monotonic ladder), the beats are spread across the width
    // (not a centered column), and there is a wide REST platform mid-climb.
    //
    //   tier 0  (floor)      : wide spawn alcove                     — teach
    //   tiers 1-3            : stalactite gauntlet, climbing          — vertical aim
    //   tier  ~mid           : WIDE REST platform (a breath)          — pause
    //   tiers mid..high      : pit-trap floor + mixed tension         — flat aim
    //   tier  count-1 (top)  : exit door FINALE near the ceiling      — signature beat
    //
    // The stalactite hazards are authored RELATIVE to each beat's own tier floor with
    // the proven gapFromFloor (175) so the apex-clearance trap geometry is preserved at
    // every elevation. Pit-trap visuals sit in the gaps between beats. Cave creatures
    // and stalagmites are scattered for the same readability the iPhone path has.
    private func buildComposedIPadLevel() {
        let count = ipadTierCount
        let lastTier = count - 1
        func tierY(_ i: Int) -> CGFloat { verticalTier(min(max(i, 0), count - 1), of: count, iphoneGround: 160) }

        // The climb is authored as a SAFE STAIRCASE. Each beat declares a desired
        // fractional progress (0 = floor, 1 = ceiling) and an optional `dip`; we then
        // WALK the current tier toward that target by AT MOST ONE tier per beat (a dip
        // forces a single -1 step). That walk-by-one rule GUARANTEES every consecutive
        // rise is <= one verticalTier step (<= maxJumpableRise=85) regardless of how
        // many tiers `count` resolves to on a given iPad — so the route fills the full
        // band on a 12.9" exactly as safely as on an 11". X spacing is hand-tuned so
        // every edge-to-edge gap stays <= maxJumpableGap=130. Beats are spread from
        // x~120 to x~2980 across the full 3200 camera-follow width (NOT a centered
        // column), heights vary (the dips), and one beat is a WIDE REST platform.
        //
        //   (centerX, width, targetFrac, dip, role)
        struct Beat { let x: CGFloat; let w: CGFloat; let frac: CGFloat; let dip: Bool }
        let specs: [Beat] = [
            Beat(x: 140,  w: 280, frac: 0.00, dip: false), // TEACH: wide tier-0 spawn alcove
            Beat(x: 360,  w: 120, frac: 0.10, dip: false), // GAUNTLET climb begins
            Beat(x: 560,  w: 110, frac: 0.20, dip: false),
            Beat(x: 760,  w: 100, frac: 0.28, dip: true ), // local dip — vary height
            Beat(x: 950,  w: 110, frac: 0.36, dip: false),
            Beat(x: 1180, w: 240, frac: 0.44, dip: false), // WIDE REST platform (a breath)
            Beat(x: 1410, w: 90,  frac: 0.52, dip: false), // PIT-TRAP floor begins
            Beat(x: 1590, w: 80,  frac: 0.58, dip: true ), // dip
            Beat(x: 1760, w: 90,  frac: 0.66, dip: false),
            Beat(x: 1950, w: 90,  frac: 0.74, dip: false),
            Beat(x: 2150, w: 100, frac: 0.82, dip: false), // MIXED TENSION near the top
            Beat(x: 2350, w: 80,  frac: 0.88, dip: true ), // dip
            Beat(x: 2540, w: 90,  frac: 0.94, dip: false),
            Beat(x: 2720, w: 100, frac: 0.98, dip: false),
            Beat(x: 2950, w: 220, frac: 1.00, dip: false), // FINALE landing on the TOP tier
        ]

        // Resolve each beat's tier via the walk-by-one rule.
        var tiers: [Int] = []
        var cur = 0
        for (idx, b) in specs.enumerated() {
            if idx == 0 {
                cur = 0
            } else if idx == specs.count - 1 {
                cur = lastTier                       // pin finale to the ceiling tier
            } else {
                let target = Int((CGFloat(lastTier) * b.frac).rounded())
                if b.dip { cur = max(0, cur - 1) }
                else if cur < target { cur += 1 }
                else if cur > target { cur -= 1 }
            }
            tiers.append(cur)
        }
        // Guarantee the second-to-last beat is within one tier of the finale so the last
        // jump is reachable (defensive; the fracs above already trend to the top).
        if specs.count >= 2 {
            var i = tiers.count - 2
            while i >= 1 && tiers[i] < tiers[i + 1] - 1 {
                tiers[i] = tiers[i + 1] - 1
                i -= 1
            }
        }

        // Build the climbing platforms. The FINAL spec (the finale landing) is the
        // same platform buildExitSection draws below, so skip it here to avoid a
        // duplicate — it stays in `specs`/`tiers` only so the walk-by-one rule validates
        // the last jump onto the top tier.
        for (idx, b) in specs.enumerated() where idx < specs.count - 1 {
            createPlatform(at: CGPoint(x: b.x, y: tierY(tiers[idx])), size: CGSize(width: b.w, height: 40))
        }

        // Nearest-beat tier lookup so hazards/decorations attach to the route's actual
        // elevation at any x (keeps every stalactite/pit authored relative to the real
        // tier floor it threatens).
        func tierNear(_ x: CGFloat) -> Int {
            var best = 0; var bestD = CGFloat.greatestFiniteMagnitude
            for (idx, b) in specs.enumerated() {
                let d = abs(b.x - x)
                if d < bestD { bestD = d; best = tiers[idx] }
            }
            return best
        }

        // Stalactite hazards staged over the climb (the vertical-aim mechanic). Authored
        // relative to each nearby beat's own tier floor with the proven gapFromFloor
        // (175) so the apex-clearance trap geometry is preserved AT EVERY elevation.
        let stalactites: [(x: CGFloat, length: CGFloat)] = [
            (x: 460,  length: 150),
            (x: 660,  length: 130),
            (x: 855,  length: 160),
            (x: 1300, length: 140),
            (x: 2050, length: 150),
            (x: 2250, length: 130),
            (x: 2440, length: 160),
            (x: 2630, length: 140),
        ]
        for s in stalactites {
            createStalactiteHazard(
                at: CGPoint(x: s.x, y: topSafeY - 15),
                length: s.length,
                gapFromFloor: 175,           // proven apex-clearance, per-tier floor
                floorY: tierY(tierNear(s.x))
            )
        }

        // Pit-trap visuals + edge cracks in the pit-trap floor section (the flat-aim
        // mechanic). Sit just below/at the route tier so they read as floor hazards.
        let pits: [(x: CGFloat, width: CGFloat)] = [
            (x: 1500, width: 50),
            (x: 1675, width: 55),
            (x: 1855, width: 55),
            (x: 2050, width: 60),
            (x: 2250, width: 55),
        ]
        for p in pits {
            let py = tierY(tierNear(p.x))
            createPitTrapVisual(at: CGPoint(x: p.x, y: py - 20), width: p.width)
            createFloorCrack(at: CGPoint(x: p.x, y: py + 18))
        }

        // Start-alcove framing wall + decorative rocks (mirrors Section 1 readability).
        let g0 = tierY(0)
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: 0, y: g0 - 20))
        wallPath.addLine(to: CGPoint(x: 0, y: size.height))
        let leftWall = SKShapeNode(path: wallPath)
        leftWall.strokeColor = strokeColor
        leftWall.lineWidth = lineWidth * 1.5
        leftWall.zPosition = 15
        levelContainer.addChild(leftWall)
        for i in 0..<4 {
            let rockX = CGFloat(i) * 60 + 30
            let rockSize = CGFloat.random(in: 6...14)
            let rock = SKShapeNode(circleOfRadius: rockSize)
            rock.fillColor = fillColor
            rock.strokeColor = strokeColor
            rock.lineWidth = lineWidth * 0.6
            rock.position = CGPoint(x: rockX, y: g0 + 20 + rockSize)
            rock.zPosition = 12
            levelContainer.addChild(rock)
        }

        // Stalagmites + creatures for visual interest, scattered along the climb.
        for (idx, b) in specs.enumerated() where idx % 2 == 1 {
            createStalagmite(at: CGPoint(x: b.x + 30, y: tierY(tiers[idx]) + 20), height: CGFloat.random(in: 15...40))
        }
        createCaveCreature(at: CGPoint(x: 760,  y: tierY(tierNear(760))  + 40))
        createCaveCreature(at: CGPoint(x: 1760, y: tierY(tierNear(1760)) + 35))
        createCaveCreature(at: CGPoint(x: 2540, y: tierY(tierNear(2540)) + 35))

        // The exit FINALE on the top tier (signature beat near the ceiling). Platform
        // and door X tightened so the door sits just past the wide top landing.
        buildExitSection(groundY: tierY(lastTier), exitCenterX: 3050, platformCenterX: 2950, platformWidth: 220)

        // Respawn checkpoints at the climb's section heads, each carrying the tier's
        // surface Y (tier + 60, the same +60 footing offset as spawnY) so a fall after a
        // checkpoint lands ON the reached tier — never back at the floor or in a gap.
        ipadCheckpoints = [
            (x: 360,  y: tierY(tiers[1])  + 60),
            (x: 950,  y: tierY(tiers[4])  + 60),
            (x: 1180, y: tierY(tiers[5])  + 60),   // the wide REST tier
            (x: 1950, y: tierY(tiers[9])  + 60),
            (x: 2720, y: tierY(tiers[13]) + 60),
        ]
    }

    // MARK: Section 1 — Start Alcove

    private func buildStartSection(groundY: CGFloat) {
        // Wide safe platform
        createPlatform(at: CGPoint(x: 150, y: groundY), size: CGSize(width: 300, height: 40))

        // Cave wall framing the alcove
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: 0, y: groundY - 20))
        wallPath.addLine(to: CGPoint(x: 0, y: size.height))
        let leftWall = SKShapeNode(path: wallPath)
        leftWall.strokeColor = strokeColor
        leftWall.lineWidth = lineWidth * 1.5
        leftWall.zPosition = 15
        levelContainer.addChild(leftWall)

        // Decorative rocks on the floor of the start area
        for i in 0..<4 {
            let rockX = CGFloat(i) * 60 + 30
            let rockSize = CGFloat.random(in: 6...14)
            let rock = SKShapeNode(circleOfRadius: rockSize)
            rock.fillColor = fillColor
            rock.strokeColor = strokeColor
            rock.lineWidth = lineWidth * 0.6
            rock.position = CGPoint(x: rockX, y: groundY + 20 + rockSize)
            rock.zPosition = 12
            levelContainer.addChild(rock)
        }

        // Small stalactite decoration above start
        createDecorativeStalactite(at: CGPoint(x: 100, y: topSafeY - 20), length: 30)
        createDecorativeStalactite(at: CGPoint(x: 200, y: topSafeY - 15), length: 40)
    }

    // MARK: Section 2 — Stalactite Gauntlet

    private func buildStalactiteGauntlet(groundY: CGFloat) {
        // Continuous ground platform through this section
        createPlatform(at: CGPoint(x: 700, y: groundY), size: CGSize(width: 600, height: 40))

        // Stalactites hanging from ceiling — must hold phone vertical to see them
        let stalactitePositions: [(x: CGFloat, length: CGFloat, gap: CGFloat)] = [
            (x: 440, length: 140, gap: 80),
            (x: 520, length: 160, gap: 80),
            (x: 590, length: 120, gap: 100),
            (x: 660, length: 180, gap: 80),
            (x: 740, length: 100, gap: 120),
            (x: 820, length: 170, gap: 80),
            (x: 880, length: 130, gap: 90),
            (x: 950, length: 150, gap: 80),
        ]

        for data in stalactitePositions {
            createStalactiteHazard(
                at: CGPoint(x: data.x, y: topSafeY - 15),
                length: data.length,
                gapFromFloor: data.gap,
                floorY: groundY
            )
        }

        // Add some stalagmites rising from the ground (non-hazard visual interest)
        let stalagmitePositions: [CGFloat] = [460, 550, 650, 780, 900]
        for sx in stalagmitePositions {
            createStalagmite(at: CGPoint(x: sx, y: groundY + 20), height: CGFloat.random(in: 20...50))
        }

        // Cave creature with glowing eyes hiding behind a stalactite
        createCaveCreature(at: CGPoint(x: 600, y: groundY + 40))
    }

    // MARK: Section 3 — Floor Trap Section

    private func buildFloorTrapSection(groundY: CGFloat) {
        // Platforms with gaps (pit traps). Must tilt phone flat to see the floor.
        // Solid sections:
        let solidPlatforms: [(x: CGFloat, width: CGFloat)] = [
            (x: 1050, width: 100),
            (x: 1200, width: 80),
            (x: 1320, width: 60),
            (x: 1440, width: 100),
            (x: 1580, width: 80),
            (x: 1720, width: 100),
        ]

        for data in solidPlatforms {
            createPlatform(at: CGPoint(x: data.x, y: groundY), size: CGSize(width: data.width, height: 40))
        }

        // Warning cracks near pit edges (visual hints even in dim light)
        let crackPositions: [CGFloat] = [1100, 1240, 1350, 1490, 1620, 1770]
        for cx in crackPositions {
            createFloorCrack(at: CGPoint(x: cx, y: groundY + 18))
        }

        // Pit trap visual markers — faint "danger" lines below platforms
        let pitPositions: [(x: CGFloat, width: CGFloat)] = [
            (x: 1150, width: 50),
            (x: 1260, width: 60),
            (x: 1380, width: 60),
            (x: 1510, width: 70),
            (x: 1650, width: 70),
        ]

        for data in pitPositions {
            createPitTrapVisual(at: CGPoint(x: data.x, y: groundY - 20), width: data.width)
        }

        // A few small stalactites to keep players on their toes
        createDecorativeStalactite(at: CGPoint(x: 1100, y: topSafeY - 20), length: 50)
        createDecorativeStalactite(at: CGPoint(x: 1400, y: topSafeY - 10), length: 60)
        createDecorativeStalactite(at: CGPoint(x: 1650, y: topSafeY - 25), length: 45)

        // Creature hiding in a pit
        createCaveCreature(at: CGPoint(x: 1380, y: groundY - 30))
    }

    // MARK: Section 4 — Mixed Section

    private func buildMixedSection(groundY: CGFloat) {
        // Platforms with gaps AND ceiling hazards
        let platforms: [(x: CGFloat, width: CGFloat)] = [
            (x: 1850, width: 120),
            (x: 2000, width: 80),
            (x: 2120, width: 100),
            (x: 2260, width: 60),
            (x: 2380, width: 80),
            (x: 2500, width: 120),
        ]

        for data in platforms {
            createPlatform(at: CGPoint(x: data.x, y: groundY), size: CGSize(width: data.width, height: 40))
        }

        // Stalactite hazards in the mixed section
        let stalactites: [(x: CGFloat, length: CGFloat)] = [
            (x: 1880, length: 150),
            (x: 2040, length: 130),
            (x: 2160, length: 170),
            (x: 2300, length: 140),
            (x: 2420, length: 160),
        ]

        // SOFTLOCK FIX: Every Section 4 stalactite x (1880/2040/2160/2300/2420)
        // sits within a mandatory gap's ±40pt range, and at gapFromFloor 70 the
        // tip was at y = platformTop(180)+70 = 250 — below Bit's jumped head apex,
        // so a mandatory jump over each gap drove Bit's head into a hazard
        // (not-completable). Raise gapFromFloor so the tip clears the worst-case
        // head apex. Worst case head top = iPad-scaled body top (180 + 64*0.85*1.25
        // = 248) + larger assumed apex (~91pt at the 620 cap) = ~339pt. With
        // gapFromFloor 175 the tip sits at 180 + 175 = 355 (>= ~340), clearing
        // the head with comfortable margin on every device and under both apex
        // assumptions (worst-case iPad/620 margin ~16pt; real clamp-500 margins
        // ~48-62pt).
        for data in stalactites {
            createStalactiteHazard(
                at: CGPoint(x: data.x, y: topSafeY - 15),
                length: data.length,
                gapFromFloor: 175,
                floorY: groundY
            )
        }

        // Pit traps in gaps
        let pits: [(x: CGFloat, width: CGFloat)] = [
            (x: 1960, width: 40),
            (x: 2060, width: 50),
            (x: 2190, width: 50),
            (x: 2320, width: 50),
            (x: 2440, width: 60),
        ]

        for data in pits {
            createPitTrapVisual(at: CGPoint(x: data.x, y: groundY - 20), width: data.width)
        }

        // Floor cracks as warnings
        let cracks: [CGFloat] = [1910, 2040, 2170, 2310, 2440, 2560]
        for cx in cracks {
            createFloorCrack(at: CGPoint(x: cx, y: groundY + 18))
        }

        // Stalagmites for visual interest
        let stalagmites: [CGFloat] = [1870, 2100, 2350, 2520]
        for sx in stalagmites {
            createStalagmite(at: CGPoint(x: sx, y: groundY + 20), height: CGFloat.random(in: 15...35))
        }

        // Cave creatures
        createCaveCreature(at: CGPoint(x: 2200, y: groundY + 35))
        createCaveCreature(at: CGPoint(x: 2450, y: topSafeY - 100))
    }

    // MARK: Section 5 — Exit Area

    /// Exit area. Defaults reproduce the original iPhone layout EXACTLY (wide platform
    /// at x:2850 w:400, door at x:3050) so the iPhone path is byte-identical. The iPad
    /// climb passes its top-tier groundY plus a tighter platform/door X so the finale
    /// lands on the ceiling-height landing it builds.
    private func buildExitSection(groundY: CGFloat,
                                  exitCenterX: CGFloat = 3050,
                                  platformCenterX: CGFloat = 2850,
                                  platformWidth: CGFloat = 400) {
        // Wide safe platform leading to exit
        createPlatform(at: CGPoint(x: platformCenterX, y: groundY), size: CGSize(width: platformWidth, height: 40))

        // Exit door (inline, matching other levels' createExitDoor pattern)
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60
        let doorPos = CGPoint(x: exitCenterX, y: groundY + 50)

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = doorPos
        frame.zPosition = 20
        levelContainer.addChild(frame)
        exitDoorFrame = frame

        // Door panels
        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10, height: doorHeight / 2 - 15))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            frame.addChild(panel)
        }

        // Handle
        let handle = SKShapeNode(circleOfRadius: 4)
        handle.fillColor = strokeColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.5
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        // Inner portal glow
        let portalSize = CGSize(width: doorWidth - 10, height: doorHeight - 10)
        let portal = SKShapeNode(rectOf: portalSize)
        portal.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.2)
        portal.strokeColor = .clear
        portal.position = doorPos
        portal.zPosition = 19
        levelContainer.addChild(portal)
        exitDoorPortal = portal

        // Portal pulse (cosmetic; gated behind Reduce Motion — the portal stays
        // drawn at its steady fill alpha when motion is reduced).
        if !systemReduceMotion {
            portal.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.6, duration: 1.0),
                .fadeAlpha(to: 0.2, duration: 1.0)
            ])))
        }

        // Physics trigger
        let exitTrigger = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exitTrigger.position = doorPos
        exitTrigger.physicsBody = SKPhysicsBody(rectangleOf: exitTrigger.size)
        exitTrigger.physicsBody?.isDynamic = false
        exitTrigger.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exitTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        exitTrigger.physicsBody?.collisionBitMask = 0
        exitTrigger.name = "exit"
        levelContainer.addChild(exitTrigger)

        // The exit door glows faintly even in total darkness.
        // Create a glow node OUTSIDE the crop node so it's always visible.
        let exitGlow = SKShapeNode(ellipseOf: CGSize(width: 50, height: 70))
        exitGlow.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.06)
        exitGlow.strokeColor = VisualConstants.Colors.accent.withAlphaComponent(0.1)
        exitGlow.lineWidth = 1
        exitGlow.glowWidth = 8
        exitGlow.position = doorPos
        exitGlow.zPosition = 5
        addChild(exitGlow)

        // Pulse the glow (cosmetic; gated behind Reduce Motion — the always-on
        // exit glow stays visible at a steady alpha so the door is still findable
        // in the dark when motion is reduced).
        if !systemReduceMotion {
            exitGlow.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.3, duration: 1.5),
                .fadeAlpha(to: 0.8, duration: 1.5)
            ])))
        }

        // Decorative archway around exit
        let archPath = CGMutablePath()
        archPath.move(to: CGPoint(x: doorPos.x - 30, y: groundY + 20))
        archPath.addLine(to: CGPoint(x: doorPos.x - 30, y: groundY + 100))
        archPath.addCurve(
            to: CGPoint(x: doorPos.x + 30, y: groundY + 100),
            control1: CGPoint(x: doorPos.x - 30, y: groundY + 130),
            control2: CGPoint(x: doorPos.x + 30, y: groundY + 130)
        )
        archPath.addLine(to: CGPoint(x: doorPos.x + 30, y: groundY + 20))
        let arch = SKShapeNode(path: archPath)
        arch.strokeColor = strokeColor
        arch.lineWidth = lineWidth
        arch.fillColor = .clear
        arch.zPosition = 18
        levelContainer.addChild(arch)

        // Arrow hint above exit
        let arrow = createArrow()
        arrow.position = CGPoint(x: doorPos.x, y: groundY + 140)
        arrow.zPosition = 25
        // Bob is cosmetic; gated behind Reduce Motion. The arrow stays drawn at a
        // fixed position so the exit hint is still present when motion is reduced.
        if !systemReduceMotion {
            arrow.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: -6, duration: 0.4),
                .moveBy(x: 0, y: 6, duration: 0.4)
            ])))
        }
        levelContainer.addChild(arrow)
    }

    // MARK: - Death Zone

    private func buildDeathZone() {
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: levelWidth / 2, y: deathZoneY)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: levelWidth * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        levelContainer.addChild(deathZone)
    }

    // MARK: - Platform Factory

    @discardableResult
    private func createPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        levelContainer.addChild(container)

        // Main surface
        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.name = "surface"
        surface.zPosition = 5
        container.addChild(surface)

        // 3D depth effect (top edge highlight)
        let depth: CGFloat = 5
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -platformSize.width / 2, y: platformSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2, y: platformSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.5
        depthLine.zPosition = 4
        container.addChild(depthLine)

        // Rocky texture lines on platform surface
        for i in 0..<Int(platformSize.width / 25) {
            let texturePath = CGMutablePath()
            let tx = -platformSize.width / 2 + CGFloat(i) * 25 + CGFloat.random(in: 5...20)
            let ty = CGFloat.random(in: -platformSize.height / 4...platformSize.height / 4)
            texturePath.move(to: CGPoint(x: tx, y: ty))
            texturePath.addLine(to: CGPoint(x: tx + CGFloat.random(in: 5...15), y: ty + CGFloat.random(in: -3...3)))
            let texture = SKShapeNode(path: texturePath)
            texture.strokeColor = strokeColor.withAlphaComponent(0.3)
            texture.lineWidth = 1.0
            texture.zPosition = 6
            container.addChild(texture)
        }

        // Physics
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    // MARK: - Stalactite Hazard Factory

    private func createStalactiteHazard(at position: CGPoint, length: CGFloat, gapFromFloor: CGFloat, floorY: CGFloat) {
        let container = SKNode()
        let platformTopY = floorY + 20
        container.position = CGPoint(x: position.x, y: platformTopY + gapFromFloor + length)
        container.zPosition = 20
        levelContainer.addChild(container)

        // Main stalactite shape — irregular triangle pointing down
        let stalPath = CGMutablePath()
        let baseWidth = CGFloat.random(in: 15...30)
        let tipOffset = CGFloat.random(in: -5...5)

        stalPath.move(to: CGPoint(x: -baseWidth / 2, y: 0))

        // Left side with bumps
        let leftBump1 = CGPoint(x: -baseWidth / 3 + CGFloat.random(in: -3...3), y: -length * 0.3)
        let leftBump2 = CGPoint(x: -baseWidth / 5 + CGFloat.random(in: -2...2), y: -length * 0.7)
        stalPath.addLine(to: leftBump1)
        stalPath.addLine(to: leftBump2)

        // Tip
        stalPath.addLine(to: CGPoint(x: tipOffset, y: -length))

        // Right side with bumps
        let rightBump2 = CGPoint(x: baseWidth / 5 + CGFloat.random(in: -2...2), y: -length * 0.7)
        let rightBump1 = CGPoint(x: baseWidth / 3 + CGFloat.random(in: -3...3), y: -length * 0.3)
        stalPath.addLine(to: rightBump2)
        stalPath.addLine(to: rightBump1)

        stalPath.addLine(to: CGPoint(x: baseWidth / 2, y: 0))
        stalPath.closeSubpath()

        let stalShape = SKShapeNode(path: stalPath)
        stalShape.fillColor = fillColor
        stalShape.strokeColor = strokeColor
        stalShape.lineWidth = lineWidth
        container.addChild(stalShape)

        // Detail lines on the stalactite surface
        for i in 0..<3 {
            let detailY = -length * (0.2 + CGFloat(i) * 0.25)
            let detailPath = CGMutablePath()
            detailPath.move(to: CGPoint(x: -baseWidth / 4, y: detailY))
            detailPath.addLine(to: CGPoint(x: baseWidth / 4, y: detailY + CGFloat.random(in: -3...3)))
            let detail = SKShapeNode(path: detailPath)
            detail.strokeColor = strokeColor.withAlphaComponent(0.4)
            detail.lineWidth = 1.0
            container.addChild(detail)
        }

        // Drip particle effect at the tip
        let dripTimer = SKAction.repeatForever(.sequence([
            .wait(forDuration: Double.random(in: 2.0...5.0)),
            .run { [weak self] in
                self?.spawnWaterDrip(at: container.position + CGPoint(x: tipOffset, y: -length))
            }
        ]))
        container.run(dripTimer, withKey: "drip")

        // Hazard physics body — covers the stalactite
        let hazardBody = SKPhysicsBody(polygonFrom: stalPath)
        hazardBody.isDynamic = false
        hazardBody.categoryBitMask = PhysicsCategory.hazard
        hazardBody.contactTestBitMask = PhysicsCategory.player
        hazardBody.collisionBitMask = 0
        container.physicsBody = hazardBody

        stalactiteNodes.append(container)
    }

    // MARK: - Decorative Stalactite (non-hazard)

    private func createDecorativeStalactite(at position: CGPoint, length: CGFloat) {
        let container = SKNode()
        container.position = position
        container.zPosition = 12
        levelContainer.addChild(container)

        let stalPath = CGMutablePath()
        let baseWidth = CGFloat.random(in: 10...18)
        stalPath.move(to: CGPoint(x: -baseWidth / 2, y: 0))
        stalPath.addLine(to: CGPoint(x: -baseWidth / 4, y: -length * 0.6))
        stalPath.addLine(to: CGPoint(x: 0, y: -length))
        stalPath.addLine(to: CGPoint(x: baseWidth / 4, y: -length * 0.6))
        stalPath.addLine(to: CGPoint(x: baseWidth / 2, y: 0))
        stalPath.closeSubpath()

        let shape = SKShapeNode(path: stalPath)
        shape.fillColor = fillColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth * 0.7
        container.addChild(shape)
    }

    // MARK: - Stalagmite (rising from floor, non-hazard)

    private func createStalagmite(at position: CGPoint, height: CGFloat) {
        let container = SKNode()
        container.position = position
        container.zPosition = 8
        levelContainer.addChild(container)

        let path = CGMutablePath()
        let baseWidth = height * 0.5
        path.move(to: CGPoint(x: -baseWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: -baseWidth / 4, y: height * 0.5))
        path.addLine(to: CGPoint(x: CGFloat.random(in: -2...2), y: height))
        path.addLine(to: CGPoint(x: baseWidth / 4, y: height * 0.5))
        path.addLine(to: CGPoint(x: baseWidth / 2, y: 0))
        path.closeSubpath()

        let shape = SKShapeNode(path: path)
        shape.fillColor = fillColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth * 0.6
        container.addChild(shape)
    }

    // MARK: - Floor Crack Warning

    private func createFloorCrack(at position: CGPoint) {
        let crackPath = CGMutablePath()
        crackPath.move(to: CGPoint(x: -8, y: 0))
        crackPath.addLine(to: CGPoint(x: CGFloat.random(in: -3...3), y: -CGFloat.random(in: 5...12)))
        crackPath.addLine(to: CGPoint(x: CGFloat.random(in: -5...5), y: -CGFloat.random(in: 12...20)))
        crackPath.addLine(to: CGPoint(x: 8, y: 0))

        let crack = SKShapeNode(path: crackPath)
        crack.strokeColor = strokeColor.withAlphaComponent(0.5)
        crack.lineWidth = lineWidth * 0.5
        crack.position = position
        crack.zPosition = 7
        levelContainer.addChild(crack)
    }

    // MARK: - Pit Trap Visual

    private func createPitTrapVisual(at position: CGPoint, width: CGFloat) {
        let container = SKNode()
        container.position = position
        container.zPosition = 3
        levelContainer.addChild(container)

        // Faint "void" lines descending into darkness
        for i in 0..<4 {
            let lineNode = SKShapeNode()
            let linePath = CGMutablePath()
            let y = CGFloat(i) * -15
            linePath.move(to: CGPoint(x: -width / 2, y: y))
            linePath.addLine(to: CGPoint(x: width / 2, y: y))
            lineNode.path = linePath
            lineNode.strokeColor = strokeColor.withAlphaComponent(0.15 - CGFloat(i) * 0.03)
            lineNode.lineWidth = 1.0
            container.addChild(lineNode)
        }

        // Skull icon warning
        let skull = createSkullIcon()
        skull.position = CGPoint(x: 0, y: -25)
        skull.alpha = 0.2
        skull.setScale(0.6)
        container.addChild(skull)

        floorTrapMarkers.append(container)
    }

    // MARK: - Skull Warning Icon

    private func createSkullIcon() -> SKNode {
        let skull = SKNode()

        // Head
        let head = SKShapeNode(circleOfRadius: 8)
        head.fillColor = .clear
        head.strokeColor = strokeColor
        head.lineWidth = 1.5
        skull.addChild(head)

        // Eyes
        let leftEye = SKShapeNode(circleOfRadius: 2)
        leftEye.fillColor = strokeColor
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -3, y: 2)
        skull.addChild(leftEye)

        let rightEye = SKShapeNode(circleOfRadius: 2)
        rightEye.fillColor = strokeColor
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 3, y: 2)
        skull.addChild(rightEye)

        // Jaw line
        let jawPath = CGMutablePath()
        jawPath.move(to: CGPoint(x: -4, y: -4))
        jawPath.addLine(to: CGPoint(x: 4, y: -4))
        let jaw = SKShapeNode(path: jawPath)
        jaw.strokeColor = strokeColor
        jaw.lineWidth = 1.0
        skull.addChild(jaw)

        return skull
    }

    // MARK: - Cave Creature (glowing eyes)

    private func createCaveCreature(at position: CGPoint) {
        let creature = SKNode()
        creature.position = position
        creature.zPosition = 15
        creature.name = "cave_creature"
        levelContainer.addChild(creature)

        // Two glowing eyes
        let eyeSpacing: CGFloat = 10
        let eyeRadius: CGFloat = 3

        let leftEye = SKShapeNode(circleOfRadius: eyeRadius)
        leftEye.fillColor = VisualConstants.Colors.accent
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -eyeSpacing / 2, y: 0)
        leftEye.glowWidth = 4
        creature.addChild(leftEye)

        let rightEye = SKShapeNode(circleOfRadius: eyeRadius)
        rightEye.fillColor = VisualConstants.Colors.accent
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: eyeSpacing / 2, y: 0)
        rightEye.glowWidth = 4
        creature.addChild(rightEye)

        // Blink animation
        let blink = SKAction.repeatForever(.sequence([
            .wait(forDuration: Double.random(in: 2.0...6.0)),
            .run {
                leftEye.run(.sequence([.scaleY(to: 0.1, duration: 0.08), .scaleY(to: 1.0, duration: 0.08)]))
                rightEye.run(.sequence([.scaleY(to: 0.1, duration: 0.08), .scaleY(to: 1.0, duration: 0.08)]))
            }
        ]))
        creature.run(blink, withKey: "blink")

        caveCreatures.append(creature)
    }

    /// When the flashlight illuminates a creature, it scurries away.
    private func updateCaveCreatures() {
        guard isFlashlightOn else { return }

        for creature in caveCreatures {
            guard creature.parent != nil else { continue }

            let distX = abs(creature.position.x - bit.position.x)
            let distY = abs(creature.position.y - bit.position.y)
            let lightReach = max(currentLightWidth, currentLightHeight) * 0.6

            if distX < lightReach && distY < lightReach {
                // Flee!
                creature.removeAction(forKey: "blink")
                let fleeDirection: CGFloat = creature.position.x > bit.position.x ? 1 : -1
                let fleeAction = SKAction.sequence([
                    .group([
                        .moveBy(x: fleeDirection * 200, y: 0, duration: 0.4),
                        .fadeOut(withDuration: 0.4)
                    ]),
                    .removeFromParent()
                ])
                creature.run(fleeAction)
            }
        }
        // Remove fled creatures from tracking
        caveCreatures.removeAll { $0.parent == nil }
    }

    // MARK: - Water Drip Effect

    private func spawnWaterDrip(at position: CGPoint) {
        let drip = SKShapeNode(circleOfRadius: 2)
        drip.fillColor = strokeColor.withAlphaComponent(0.4)
        drip.strokeColor = .clear
        drip.position = position
        drip.zPosition = 25
        levelContainer.addChild(drip)

        drip.run(.sequence([
            .moveBy(x: 0, y: -80, duration: 0.6),
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))
    }

    // MARK: - Arrow Helper

    private func createArrow() -> SKShapeNode {
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 10))
        path.addLine(to: CGPoint(x: -8, y: 0))
        path.addLine(to: CGPoint(x: -3, y: 0))
        path.addLine(to: CGPoint(x: -3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: 0))
        path.addLine(to: CGPoint(x: 8, y: 0))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = strokeColor
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.6
        arrow.zRotation = .pi
        return arrow
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        // LEGIBILITY FIX: the panel used to live inside levelContainer (the
        // SKCropNode masked to the flashlight beam), so the "turn on your
        // flashlight" goal was clipped by the very darkness it tells you to dispel
        // — you couldn't read the instruction until you'd already done the thing.
        // Re-parent it to the camera as a fixed HUD overlay (mirrors L8's
        // scene-anchored panel), outside the crop, so it's always legible and
        // stays on-screen as the camera scrolls. zPosition 200 preserved.
        instructionPanel = SKNode()
        // Camera-local coordinates: origin maps to screen centre, so place the
        // panel in the upper-centre of the viewport on every device width.
        instructionPanel?.position = CGPoint(x: 0, y: topSafeY - size.height / 2 - 80)
        instructionPanel?.zPosition = 200
        gameCamera.addChild(instructionPanel!)

        // Panel background
        let panelBG = SKShapeNode(rectOf: CGSize(width: 240, height: 100), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        instructionPanel?.addChild(panelBG)

        // Flashlight icon
        let flashlightIcon = createFlashlightIcon()
        flashlightIcon.position = CGPoint(x: -70, y: 5)
        instructionPanel?.addChild(flashlightIcon)

        // Phone tilt icon
        let phoneIcon = createPhoneTiltIcon()
        phoneIcon.position = CGPoint(x: 20, y: 10)
        instructionPanel?.addChild(phoneIcon)

        // Text line 1
        let label1 = SKLabelNode(text: "TURN ON YOUR")
        label1.fontName = "Menlo-Bold"
        label1.fontSize = 11
        label1.fontColor = strokeColor
        label1.position = CGPoint(x: 0, y: -25)
        instructionPanel?.addChild(label1)

        // Text line 2
        let label2 = SKLabelNode(text: "FLASHLIGHT")
        label2.fontName = "Menlo-Bold"
        label2.fontSize = 11
        label2.fontColor = VisualConstants.Colors.accent
        label2.position = CGPoint(x: 0, y: -40)
        instructionPanel?.addChild(label2)

        // Pulsing animation (cosmetic; gated behind Reduce Motion — the panel
        // holds a steady, fully-legible alpha when motion is reduced).
        if !systemReduceMotion {
            instructionPanel?.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.6, duration: 1.0),
                .fadeAlpha(to: 1.0, duration: 1.0)
            ])))
        }
    }

    private func createFlashlightIcon() -> SKNode {
        let icon = SKNode()

        // Flashlight body
        let bodyPath = CGMutablePath()
        bodyPath.addRoundedRect(in: CGRect(x: -6, y: -18, width: 12, height: 36), cornerWidth: 3, cornerHeight: 3)
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.7
        icon.addChild(body)

        // Light cone at the top
        let conePath = CGMutablePath()
        conePath.move(to: CGPoint(x: -6, y: 18))
        conePath.addLine(to: CGPoint(x: -12, y: 30))
        conePath.addLine(to: CGPoint(x: 12, y: 30))
        conePath.addLine(to: CGPoint(x: 6, y: 18))
        conePath.closeSubpath()
        let cone = SKShapeNode(path: conePath)
        cone.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.3)
        cone.strokeColor = VisualConstants.Colors.accent
        cone.lineWidth = 1.0
        icon.addChild(cone)

        return icon
    }

    private func createPhoneTiltIcon() -> SKNode {
        let icon = SKNode()

        // Phone outline
        let phone = SKShapeNode(rectOf: CGSize(width: 20, height: 34), cornerRadius: 3)
        phone.fillColor = fillColor
        phone.strokeColor = strokeColor
        phone.lineWidth = lineWidth * 0.6
        phone.zRotation = -0.4 // Tilted
        icon.addChild(phone)

        // Curved arrow indicating tilt
        let arrowPath = CGMutablePath()
        arrowPath.addArc(center: CGPoint(x: 15, y: 0), radius: 12, startAngle: .pi * 0.6, endAngle: .pi * 1.2, clockwise: false)
        let arrow = SKShapeNode(path: arrowPath)
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.5
        icon.addChild(arrow)

        // Arrowhead
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: 5, y: -8))
        headPath.addLine(to: CGPoint(x: 3, y: -14))
        headPath.addLine(to: CGPoint(x: 9, y: -10))
        let head = SKShapeNode(path: headPath)
        head.strokeColor = strokeColor
        head.lineWidth = lineWidth * 0.5
        icon.addChild(head)

        return icon
    }

    // MARK: - Ambient Glow (always visible outside crop node)

    private func setupAmbientGlow() {
        // A very faint glow around the player that's always visible,
        // independent of the crop node. Gives just enough light to see your feet.
        ambientGlow = SKShapeNode(ellipseOf: CGSize(width: 80, height: 80))
        ambientGlow.fillColor = strokeColor.withAlphaComponent(0.02)
        ambientGlow.strokeColor = strokeColor.withAlphaComponent(0.04)
        ambientGlow.lineWidth = 1
        ambientGlow.glowWidth = 3
        ambientGlow.zPosition = 5
        addChild(ambientGlow)
    }

    // MARK: - Bit Setup

    private func setupBit() {
        // Spawn on the tier-0 alcove. spawnY is ground-relative (220 on iPhone,
        // byte-identical); on iPad it tracks the lifted floor so Bit lands on the
        // wide spawn platform rather than dropping into the death zone.
        spawnPoint = CGPoint(x: 100, y: spawnY)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        levelContainer.addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
        playerController.worldWidth = levelWidth
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
        bit.clampVelocity()
        updateCamera()
        updateLightCone(deltaTime: deltaTime)
        updateAmbientGlow()
        updateCaveCreatures()
        checkSectionProgress()
        checkFallDeath()
    }

    // MARK: - Camera Following

    private func updateCamera() {
        guard let camera = gameCamera else { return }
        let targetX = max(size.width / 2, min(bit.position.x, levelWidth - size.width / 2))
        let currentX = camera.position.x
        let newX = currentX + (targetX - currentX) * 0.1
        camera.position.x = newX
    }

    // MARK: - Light Cone Update

    /// Recalculate the light cone mask every frame based on flashlight state and phone pitch.
    private func updateLightCone(deltaTime: TimeInterval) {
        let lerpSpeed: CGFloat = 8.0
        let t = min(1.0, CGFloat(deltaTime) * lerpSpeed)

        // Calculate target light dimensions
        var targetWidth: CGFloat
        var targetHeight: CGFloat
        var targetOffsetY: CGFloat
        var targetOffsetX: CGFloat

        if !isFlashlightOn {
            // Flashlight off: tiny circle around player
            targetWidth = 60
            targetHeight = 60
            targetOffsetY = 0
            targetOffsetX = 0
        } else {
            // Flashlight on: shape depends on phone pitch
            // pitch ~ -pi/2 (-1.57): vertical, beam forward (long ellipse ahead)
            // pitch ~ -pi/4 (-0.78): 45 degrees, medium spread
            // pitch ~ 0: flat/face up, wide circle at feet
            // pitch > 0: tilted back, very small circle at feet

            let normalizedPitch = max(-Double.pi / 2, min(0.3, currentPitch))

            if normalizedPitch < -1.0 {
                // Phone held vertical — long narrow beam extending ahead
                let verticalFactor = CGFloat((-normalizedPitch - 1.0) / (Double.pi / 2 - 1.0))
                targetWidth = lerp(180, 100, t: verticalFactor)
                targetHeight = lerp(300, 500, t: verticalFactor)
                // Offset the ellipse in the player's facing direction
                let facingDirection: CGFloat = bit.xScale >= 0 ? 1 : -1
                targetOffsetX = facingDirection * lerp(50, 150, t: verticalFactor)
                targetOffsetY = lerp(50, 100, t: verticalFactor)
            } else if normalizedPitch < -0.5 {
                // Phone at roughly 45 degrees — medium spread
                let midFactor = CGFloat((-normalizedPitch - 0.5) / 0.5)
                targetWidth = lerp(220, 180, t: midFactor)
                targetHeight = lerp(250, 300, t: midFactor)
                let facingDirection: CGFloat = bit.xScale >= 0 ? 1 : -1
                targetOffsetX = facingDirection * lerp(20, 50, t: midFactor)
                targetOffsetY = lerp(20, 50, t: midFactor)
            } else {
                // Phone flat or tilted back — wide circle on floor
                let flatFactor = CGFloat(max(0, -normalizedPitch) / 0.5)
                targetWidth = lerp(100, 220, t: flatFactor)
                targetHeight = lerp(100, 250, t: flatFactor)
                targetOffsetX = 0
                targetOffsetY = lerp(-30, 20, t: flatFactor)
            }
        }

        // Smooth interpolation
        currentLightWidth = lerp(currentLightWidth, targetWidth, t: t)
        currentLightHeight = lerp(currentLightHeight, targetHeight, t: t)
        currentLightOffsetX = lerp(currentLightOffsetX, targetOffsetX, t: t)
        currentLightOffsetY = lerp(currentLightOffsetY, targetOffsetY, t: t)

        // Rebuild the mask ellipse centered on the player
        let maskCenter = CGPoint(
            x: bit.position.x + currentLightOffsetX,
            y: bit.position.y + currentLightOffsetY
        )

        let ellipsePath = CGPath(
            ellipseIn: CGRect(
                x: maskCenter.x - currentLightWidth / 2,
                y: maskCenter.y - currentLightHeight / 2,
                width: currentLightWidth,
                height: currentLightHeight
            ),
            transform: nil
        )
        lightMask.path = ellipsePath
    }

    private func updateAmbientGlow() {
        ambientGlow.position = bit.position
        // Slightly bigger glow when flashlight is on
        let glowScale: CGFloat = isFlashlightOn ? 1.3 : 1.0
        ambientGlow.setScale(glowScale)
    }

    // MARK: - Section Progress Tracking

    private func checkSectionProgress() {
        if isWideCanvas {
            // iPad: tiered checkpoints carry a per-tier respawn Y so a fall after a
            // checkpoint lands ON the reached tier of the climb (not back at the floor
            // or into a gap), preserving spawn/exit reachability on the vertical route.
            for (index, cp) in ipadCheckpoints.enumerated() {
                if bit.position.x > cp.x && index > lastCheckpointReached {
                    lastCheckpointReached = index
                    resetProgressTimer()
                    spawnPoint = CGPoint(x: cp.x, y: cp.y)
                }
            }
        } else {
            // iPhone: original x-only checkpoints at the flat-cave footing height.
            for (index, checkpoint) in sectionCheckpoints.enumerated() {
                if bit.position.x > checkpoint && index > lastCheckpointReached {
                    lastCheckpointReached = index
                    resetProgressTimer()
                    spawnPoint = CGPoint(x: checkpoint, y: 220)
                }
            }
        }
    }

    // MARK: - Fall Death Detection

    private func checkFallDeath() {
        if bit.position.y < deathZoneY + 80 {
            handleDeath()
        }
    }

    // MARK: - Lerp Utility

    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .flashlightChanged(let isOn):
            let wasOn = isFlashlightOn
            isFlashlightOn = isOn

            if isOn && !wasOn {
                // Flashlight just turned on
                resetProgressTimer()
                HapticManager.shared.collect()

                // Dismiss instruction panel
                if let panel = instructionPanel {
                    panel.run(.sequence([
                        .fadeOut(withDuration: 0.3),
                        .removeFromParent()
                    ]))
                    instructionPanel = nil
                }

                // Fourth-wall commentary
                if !flashlightOnCommentShown {
                    flashlightOnCommentShown = true
                    GlitchedNarrator.present("CREATIVE USE OF HARDWARE.", in: self, style: .whisper)
                }
            }

        case .flashlightAngleChanged(let pitch):
            let oldPitch = currentPitch
            currentPitch = pitch

            // Fourth-wall commentary when held vertical for the first time
            if pitch < -1.2 && oldPitch >= -1.2 && !verticalCommentShown && isFlashlightOn {
                verticalCommentShown = true
                GlitchedNarrator.present("NOW YOU LOOK LIKE YOU'RE TAKING A SELFIE IN A CAVE.", in: self, style: .whisper)
            }

        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController.touchBegan(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController.touchMoved(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController.touchEnded(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        playerController.cancel()
    }

    // MARK: - Physics Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            bit.setGrounded(true)
            playerLanded(velocity: bit.physicsBody?.velocity.dy ?? 0)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    self?.bit.setGrounded(false)
                }
            ]))
        }
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        failLevel()
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            guard let self = self else { return }
            self.bit.setGrounded(true)
            // Reset to playing state after respawn
            GameState.shared.setState(.playing)
        }
    }

    private func handleExit() {
        guard GameState.shared.levelState == .playing else { return }
        succeedLevel()

        // Exit commentary
        if !exitCommentShown {
            exitCommentShown = true
            GlitchedNarrator.present("NOT BAD FOR PLAYING IN THE DARK.", in: self, style: .whisper)
        }

        // Unlock animation
        exitDoorFrame?.run(.sequence([
            .scale(to: 1.2, duration: 0.2),
            .scale(to: 1.0, duration: 0.1)
        ]))
        exitDoorPortal?.fillColor = VisualConstants.Colors.accent

        bit.removeAllActions()
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in
                self?.transitionToNextLevel()
            }
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Turn on your flashlight and hold your phone up to look ahead. Tilt your phone flat to light up the floor and spot pits."
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}

// MARK: - CGPoint Arithmetic Extension (private to file)

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}
