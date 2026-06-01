import SpriteKit
import UIKit

/// Level 23: Device Name
/// Concept: The game reads the device owner name and addresses the player personally.
/// A doppelganger NPC mirrors the player but follows a preset path.
/// The exit door only opens for the "real" player.
final class DeviceNameScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (platforms, doors, doppelganger path, spawn) is authored
    // in a fixed `designSize.width`-point logical course so platform spacing,
    // gaps, and the exit jump stay consistent across iPhone and iPad instead of
    // stretching to fill an iPad. The course clamps at scale 1.0 so it never
    // overflows a narrow screen; on a ~390 iPhone it stays effectively full-bleed
    // (slightly compressed), and on iPad it is centered with the surrounding
    // space filled by decoration/UI, which still keys off size.width.
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Device name state
    private var playerName: String = "PLAYER"
    private var nameDoorLabel: SKLabelNode?
    private var nameDoorBlocker: SKNode?
    private var nameDoorNode: SKNode?
    private var nameDoorOpened = false

    // Name-gate doors: the puzzle's actual lock. The mid-level name gate only
    // de-solidifies once the device name is confirmed; the END is a CLUSTER of
    // three doorways and only the one labeled with the real device name is the
    // live exit — the other two are inert decoys. The name is the key, so the
    // player must READ their name and step into the matching door (distractors
    // flank it). Doorways don't block traversal, so the player can always reach
    // their slot regardless of which one it is.
    private struct NameGateDoor {
        let node: SKNode
        let label: SKLabelNode
        let frame: SKShapeNode
        var isRealExit: Bool
        let exitBody: SKSpriteNode?   // only the real door is armed as a live exit
    }
    private var exitDoors: [NameGateDoor] = []
    /// Distractor names shown on the two decoy exit doors. Picked at gate-build
    /// time to be plausible-but-wrong; the player must match THEIR name, not one
    /// of these. Kept generic/system-y so they read as "other identities".
    private let decoyNames = ["GUEST", "ADMIN"]

    // Hardware-free safety net: if `.deviceNameRead` never arrives (e.g. simulator
    // or no device-name permission), self-trigger the same unlock chain with a
    // sensible in-scene name fallback so the puzzle can't soft-lock. Guarded by
    // `nameReceived` so the real event always wins.
    private var nameReceived = false
    private let nameFallbackKey = "name_fallback"
    private let nameFallbackDelay: TimeInterval = 5.0

    // Doppelganger
    private var doppelganger: SKNode?
    private var doppelgangerStarted = false

    // 4th wall
    private var hasShownGreeting = false

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 23)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.deviceName])
        DeviceManagerCoordinator.shared.configure(for: [.deviceName])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createDoppelganger()
        showOpeningNarration()
        setupBit()
        scheduleNameFallback()
    }

    /// Hardware-free safety net. If the real `.deviceNameRead` event never fires
    /// (simulator / no permission), drive the same unlock chain with a sensible
    /// in-scene name after a short delay. No-op if the real name already arrived.
    private func scheduleNameFallback() {
        run(.sequence([
            .wait(forDuration: nameFallbackDelay),
            .run { [weak self] in
                guard let self, !self.nameReceived else { return }
                self.updatePlayerName(self.resolveFallbackName())
            }
        ]), withKey: nameFallbackKey)
    }

    /// Sensible name fallback when no `.deviceNameRead` event arrives. Reads the
    /// device name directly and extracts the owner from the common possessive
    /// pattern ("James's iPhone" -> "JAMES"). On iOS 16+ the system returns a
    /// generic model name without Local Network permission ("iPhone"/"iPad"),
    /// and the "CAN'T DO THIS?" hardware-fallback posts "PLAYER" — both of which
    /// resolve to "PLAYER" here so the door cluster always has a matchable key.
    private func resolveFallbackName() -> String {
        let raw = UIDevice.current.name
        // "Name's iPhone" -> "Name"
        if let range = raw.range(of: "'s ", options: .caseInsensitive) {
            let owner = String(raw[raw.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !owner.isEmpty { return owner }
        }
        let lower = raw.lowercased()
        // Generic model names (no owner) -> friendly default.
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || lower == "iphone" || lower == "ipad" || lower == "ipod touch" {
            return "PLAYER"
        }
        // A custom-but-non-possessive device name is still a usable identity.
        return raw
    }

    // MARK: - Setup

    private func setupBackground() {
        // Name tag decorations
        for i in 0..<5 {
            let tag = createNameTag(width: 40, height: 20)
            tag.position = CGPoint(x: CGFloat(i) * 120 + 80, y: topSafeY - 50)
            tag.alpha = 0.1
            tag.zPosition = -10
            addChild(tag)
        }
    }

    private func createNameTag(width: CGFloat, height: CGFloat) -> SKNode {
        let container = SKNode()

        let body = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 3)
        body.fillColor = .clear
        body.strokeColor = strokeColor
        body.lineWidth = 1.5
        container.addChild(body)

        let line = SKShapeNode(rectOf: CGSize(width: width * 0.8, height: 1))
        line.fillColor = strokeColor
        line.strokeColor = .clear
        line.position = CGPoint(x: 0, y: -3)
        container.addChild(line)

        return container
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 23")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Gameplay is authored in fixed logical course space (0...430) so the
        // platform spacing, gaps, and the final exit jump stay constant across
        // iPhone/iPad. Logical layout: ≤ ~50-pt edge-to-edge gaps and a single
        // 30-pt rise — all inside the safe ~120-pt jump reach / ~91-pt rise.
        // (Heights/Y are left on their original scaling, matching L3.)
        createPlatform(at: CGPoint(x: courseX(45), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        createPlatform(at: CGPoint(x: courseX(145), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        createNameDoor(at: CGPoint(x: courseX(185), y: groundY + 45))

        createPlatform(at: CGPoint(x: courseX(230), y: groundY), size: CGSize(width: courseLen(50), height: 30))
        createPlatform(at: CGPoint(x: courseX(285), y: groundY + 30), size: CGSize(width: courseLen(40), height: 25))

        // Final platform widened to host the THREE-door name cluster. Logical
        // span 310...430 (center x=370, w=120): its LEFT edge (310) leaves only a
        // ~5-pt edge-to-edge gap from platform P4 (right edge logical 305), so the
        // approach jump stays trivially within the ~120-pt reach. Heights/Y match
        // the rest of the course (groundY, single 30-pt rise to door sills).
        createPlatform(at: CGPoint(x: courseX(370), y: groundY), size: CGSize(width: courseLen(120), height: 30))

        // Decision point: three doors, only the one matching the device name is
        // the live exit. Logical x = 332 / 372 / 412, sills at groundY + 50.
        createExitDoorCluster(slotLogicalXs: [332, 372, 412], sillY: groundY + 50)

        // Death zone — stays full-width (centered at size.width/2) so it always
        // catches falls regardless of where the centered course sits.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createPlatform(at position: CGPoint, size: CGSize) {
        let platform = SKNode()
        platform.position = position

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)
    }

    private func createNameDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "name_door"

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: 10, height: 60))
        frame.fillColor = strokeColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Name label - will update when name is received
        let label = SKLabelNode(text: "PLAYER'S DOOR")
        label.fontName = "Menlo-Bold"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: 35)
        label.zPosition = 50
        door.addChild(label)
        nameDoorLabel = label

        addChild(door)
        nameDoorNode = door

        // Physical blocker. Unlike the old blind 2-second auto-open, this gate is
        // genuinely NAME-gated: it stays solid until the device name is confirmed
        // and the gate label matches `playerName` (it always will — the gate is
        // keyed to the player — but the OPEN is now caused by reading you, not a
        // timer). Stored so `openNameGate()` can de-solidify it on confirmation.
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 60))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(blocker)
        nameDoorBlocker = blocker
    }

    /// Open the mid-level name gate once the device name has been confirmed.
    /// The gate is the player's own door, so a confirmed name always opens it —
    /// but it is now driven by reading the name, not a fixed timer. No-op until
    /// the name arrives.
    private func openNameGate() {
        guard nameReceived, !nameDoorOpened, let door = nameDoorNode else { return }
        nameDoorOpened = true
        nameDoorBlocker?.physicsBody?.categoryBitMask = 0
        // The gate is a vertical WALL beside the path, not a floor the player
        // stands on, so de-solidifying it can't strand grounded state.
        door.run(.sequence([
            .moveBy(x: 0, y: 60, duration: 0.4),
            .fadeAlpha(to: 0.3, duration: 0.2)
        ]))
    }

    /// Build the END decision: a row of doorways, exactly ONE of which is the
    /// live exit (the door labeled with the real device name). The others are
    /// decoys labeled with distractor identities. The device name is the literal
    /// KEY — the player must read their name (greeted by the OS) and step into
    /// the matching door. Doorways do NOT block lateral traversal (so the player
    /// can always reach whichever slot is theirs); only the matching door's exit
    /// body is armed. Labels are placeholders until the name resolves, then
    /// `assignDoorIdentities()` slots the real name in and arms its exit.
    private func createExitDoorCluster(slotLogicalXs: [CGFloat], sillY: CGFloat) {
        let doorWidth: CGFloat = 30
        for (index, logicalX) in slotLogicalXs.enumerated() {
            let position = CGPoint(x: courseX(logicalX), y: sillY)

            let door = SKNode()
            door.position = position
            door.name = "exit_door_\(index)"

            // Visual doorway only — no physics blocker, so the player can walk
            // freely across the platform and choose. The wrong doors simply
            // don't complete the level (no armed exit body).
            let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: 60))
            frame.fillColor = fillColor
            frame.strokeColor = strokeColor
            frame.lineWidth = lineWidth
            door.addChild(frame)

            let label = SKLabelNode(text: "?")
            label.fontName = "Menlo-Bold"
            label.fontSize = 9
            label.fontColor = strokeColor
            label.position = CGPoint(x: 0, y: 38)
            label.zPosition = 50
            door.addChild(label)

            addChild(door)

            // Pre-built exit body for this slot, inert until this slot is chosen
            // as the real door (category flipped to .exit in assignDoorIdentities).
            let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: 60))
            exit.position = position
            exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
            exit.physicsBody?.isDynamic = false
            exit.physicsBody?.categoryBitMask = 0   // inert until armed
            exit.physicsBody?.collisionBitMask = 0
            exit.name = "exit_\(index)"
            addChild(exit)

            exitDoors.append(NameGateDoor(node: door, label: label, frame: frame, isRealExit: false, exitBody: exit))
        }
    }

    /// Slot the confirmed device name into one door and distractors into the
    /// rest, then ARM the matching door as the live exit and leave the decoys
    /// inert. Always produces exactly one live exit, so the level is completable
    /// for any resolved name (including the "PLAYER" hardware/sim fallback).
    private func assignDoorIdentities() {
        guard !exitDoors.isEmpty else { return }

        // Real door slot derived from the name so it isn't always the middle one
        // (no positional tell), but deterministic per name.
        let realIndex = Int(UInt(bitPattern: playerName.hashValue) % UInt(exitDoors.count))
        var decoyQueue = decoyNames

        for index in exitDoors.indices {
            var door = exitDoors[index]
            if index == realIndex {
                door.isRealExit = true
                door.label.text = playerName
                // Arm the live exit body.
                door.exitBody?.physicsBody?.categoryBitMask = PhysicsCategory.exit
                // Subtle "open / lit" treatment so the matching door reads as the
                // one that accepts you (alongside the name label and narration).
                door.frame.fillColor = strokeColor
                door.frame.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.55, duration: 0.6),
                    .fadeAlpha(to: 1.0, duration: 0.6)
                ])))
            } else {
                let decoy = decoyQueue.isEmpty ? "GUEST" : decoyQueue.removeFirst()
                door.label.text = decoy
                // Decoys stay inert closed doorways.
            }
            exitDoors[index] = door
        }
    }

    /// The logical x (course space) of the real exit door, for routing feedback /
    /// the doppelganger toward the correct slot. Falls back to the cluster center.
    private var realExitPosition: CGPoint {
        if let real = exitDoors.first(where: { $0.isRealExit }) {
            return real.node.position
        }
        return CGPoint(x: courseX(372), y: 210)
    }

    /// A decoy door position the doppelganger commits to (and is rejected at), so
    /// it never sits on the real exit. Falls back to a cluster edge.
    private var doppelgangerTargetPosition: CGPoint {
        if let decoy = exitDoors.first(where: { !$0.isRealExit }) {
            return decoy.node.position
        }
        return CGPoint(x: courseX(332), y: 210)
    }

    private func createDoppelganger() {
        let doppel = SKNode()
        doppel.name = "doppelganger"
        doppel.zPosition = 90

        // Dark-filled version of the bit character shape (simplified silhouette)
        // Helmet
        let helmetPath = CGMutablePath()
        helmetPath.addRoundedRect(in: CGRect(x: -14, y: 10, width: 28, height: 28), cornerWidth: 10, cornerHeight: 10)
        let helmet = SKShapeNode(path: helmetPath)
        helmet.fillColor = strokeColor
        helmet.strokeColor = strokeColor
        helmet.lineWidth = 1.5
        doppel.addChild(helmet)

        // Body
        let bodyPath = CGMutablePath()
        bodyPath.addRoundedRect(in: CGRect(x: -12, y: -14, width: 24, height: 28), cornerWidth: 6, cornerHeight: 6)
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = strokeColor
        body.strokeColor = strokeColor
        body.lineWidth = 1.5
        doppel.addChild(body)

        // Legs
        for xOff: CGFloat in [-8, 8] {
            let legPath = CGMutablePath()
            legPath.addRoundedRect(in: CGRect(x: -4, y: -14, width: 8, height: 18), cornerWidth: 3, cornerHeight: 3)
            let leg = SKShapeNode(path: legPath)
            leg.fillColor = strokeColor
            leg.strokeColor = strokeColor
            leg.lineWidth = 1.5
            leg.position = CGPoint(x: xOff, y: -18)
            doppel.addChild(leg)
        }

        // Visor (white slit on dark helmet)
        let visorPath = CGMutablePath()
        visorPath.addRoundedRect(in: CGRect(x: -9, y: -5, width: 18, height: 10), cornerWidth: 5, cornerHeight: 5)
        let visor = SKShapeNode(path: visorPath)
        visor.fillColor = SKColor(white: 0.9, alpha: 0.8)
        visor.strokeColor = .clear
        visor.position = CGPoint(x: 0, y: 22)
        doppel.addChild(visor)

        // "NOT YOU" label
        let label = SKLabelNode(text: "???")
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: 45)
        doppel.addChild(label)

        doppel.position = CGPoint(x: courseX(90), y: 200)
        doppel.alpha = 0 // Hidden until triggered

        doppelganger = doppel
        addChild(doppel)
    }

    private func startDoppelgangerRace() {
        guard !doppelgangerStarted, let doppel = doppelganger else { return }
        doppelgangerStarted = true

        doppel.alpha = 1.0

        // The doppelganger genuinely RACES the player to the door cluster: it
        // sprints the same platform route at a pace that puts it in real
        // competition with a player who dawdles. But it does NOT know your name,
        // so it commits to a DECOY door and is rejected there — it never sits on
        // (or blocks) the real exit, so completability is independent of it.
        // The player wins by reading their name and taking the matching door.
        let groundY: CGFloat = 160
        let decoyTarget = doppelgangerTargetPosition

        // Waypoints route through the centered platforms toward a decoy slot.
        let path = CGMutablePath()
        path.move(to: doppel.position)
        path.addLine(to: CGPoint(x: courseX(230), y: groundY + 40))
        path.addLine(to: CGPoint(x: courseX(285), y: groundY + 55))
        path.addLine(to: CGPoint(x: decoyTarget.x, y: groundY + 40))

        // 3.0s sprint (was a leisurely 4.0s scripted stroll) so it is a real
        // pace threat to a hesitating player rather than a guaranteed loser.
        let followPath = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 3.0)

        doppel.run(.sequence([
            followPath,
            .run { [weak self] in
                self?.doppelgangerRejected()
            }
        ]))
    }

    private func doppelgangerRejected() {
        guard let doppel = doppelganger else { return }

        // In-world rejection feedback, anchored over the DECOY door the
        // doppelganger just failed to open (points at that element, so it stays
        // a positioned HUD label rather than a narrator line).
        let decoyTarget = doppelgangerTargetPosition
        let rejected = SKLabelNode(text: "ACCESS DENIED: NOT \(playerName)")
        rejected.fontName = "Menlo-Bold"
        rejected.fontSize = 10
        rejected.fontColor = strokeColor
        rejected.position = CGPoint(x: decoyTarget.x, y: 280)
        rejected.zPosition = 300
        addChild(rejected)
        rejected.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.5), .removeFromParent()]))

        // Doppelganger dissolves at the wrong door.
        doppel.run(.sequence([
            .repeat(.sequence([
                .moveBy(x: CGFloat.random(in: -3...3), y: 0, duration: 0.05),
                .moveBy(x: CGFloat.random(in: -3...3), y: 0, duration: 0.05)
            ]), count: 10),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))

        // Spotlight the REAL door so the player knows which slot is theirs (the
        // doppelganger having ruled out a decoy). Points at the real exit element.
        let real = realExitPosition
        let openLabel = SKLabelNode(text: "\(playerName) — THIS WAY")
        openLabel.fontName = "Menlo-Bold"
        openLabel.fontSize = 10
        openLabel.fontColor = strokeColor
        openLabel.position = CGPoint(x: real.x, y: 120)
        openLabel.zPosition = 300
        addChild(openLabel)
        openLabel.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func showOpeningNarration() {
        // 4th-wall opening aside — the OS announcing it knows you. Migrated from
        // an ad-hoc top-band panel to the shared narrator (reserved lower-center
        // band, full opacity, reduce-motion aware). Fires at the same trigger
        // point (scene setup). Wording preserved.
        GlitchedNarrator.present("I KNOW WHO YOU ARE. THE DOOR KNOWS TOO.", in: self, style: .alert)
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: courseX(45), y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Name Handling

    private func updatePlayerName(_ name: String) {
        // Whichever path arrives first (real event or fallback) wins; the other
        // is suppressed so the doppelganger race never starts twice.
        guard !nameReceived else { return }
        nameReceived = true
        removeAction(forKey: nameFallbackKey)

        // Normalize: the `.deviceNameRead` event can carry a generic model name
        // on iOS 16+ (no Local Network permission) or the "PLAYER" hardware
        // fallback. Run it through the same sensible resolver so a usable,
        // matchable identity is always shown on the doors.
        playerName = normalizedName(name)

        // The mid-level gate's own label points at that gate (kept in place).
        nameDoorLabel?.text = "\(playerName)'S DOOR"

        // Open the player's name gate (now caused by reading the name) and slot
        // the real name into one END door while decoys fill the rest.
        openNameGate()
        assignDoorIdentities()

        // Show the 4th-wall greeting (narrator).
        showGreeting()

        // The doppelganger sets off to race for a decoy door.
        run(.sequence([
            .wait(forDuration: 3.0),
            .run { [weak self] in
                self?.startDoppelgangerRace()
            }
        ]))
    }

    /// Apply the fallback resolver's owner-extraction / generic-name handling to
    /// any incoming name, then uppercase for the game's terminal voice.
    private func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if trimmed.isEmpty || lower == "iphone" || lower == "ipad" || lower == "ipod touch" {
            return "PLAYER"
        }
        if let range = trimmed.range(of: "'s ", options: .caseInsensitive) {
            let owner = String(trimmed[trimmed.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !owner.isEmpty { return owner.uppercased() }
        }
        return trimmed.uppercased()
    }

    private func showGreeting() {
        guard !hasShownGreeting else { return }
        hasShownGreeting = true

        // 4th-wall greeting + aside — the OS personally addressing the player by
        // their device name. Migrated from ad-hoc top-band labels to the shared
        // narrator (lower-center band, full opacity, reduce-motion aware). Fires
        // at the same trigger (on name confirmation). Wording preserved; the two
        // lines are sequenced so the follow-up replaces the greeting as before.
        GlitchedNarrator.present("HELLO, \(playerName). I'VE BEEN EXPECTING YOU.", in: self, style: .alert)
        run(.sequence([
            .wait(forDuration: 2.6),
            .run { [weak self] in
                guard let self else { return }
                GlitchedNarrator.present("NOT LIKE I HAD A CHOICE - I LITERALLY LIVE ON YOUR DEVICE.", in: self, style: .whisper)
            }
        ]))
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .deviceNameRead(let name):
            updatePlayerName(name)
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

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
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
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            run(.sequence([.wait(forDuration: 0.05), .run { [weak self] in self?.bit.setGrounded(false) }]))
        }
    }

    // MARK: - Death / Exit

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        GlitchedNarrator.dismiss(in: self)
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Your device knows your name..."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        removeAction(forKey: nameFallbackKey)
        GlitchedNarrator.dismiss(in: self)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
