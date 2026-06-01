import SpriteKit
import UIKit

/// # GlitchedNarrator
///
/// The shared 4th-wall *narrator* presenter — the canonical way for the OS to
/// "talk to" the player. Use this anywhere a level wants the system's voice to
/// intrude (taunts, hints with personality, boss declarations, eerie asides).
///
/// ## Why this exists
/// Pre-audit, levels hand-rolled commentary as ad-hoc `SKLabelNode`s with
/// inconsistent and easily-missed styling (`fontSize = 8`, `alpha = 0.5`,
/// arbitrary placement that collided with the TITLE / PAUSE / instruction
/// panels). The narrator voice is the game's signature — it must be *consistent,
/// legible, and on-brand* on every device. This presenter centralizes:
///
/// * **Typography tokens** — `VisualConstants.Fonts` / `.Colors`, a readable
///   size floor, and **full opacity by default** (the line is the message, not
///   background texture).
/// * **A glitch / typewriter reveal** — character-by-character type-on plus an
///   RGB-split (chromatic aberration) flicker, the established "corrupted OS"
///   feel used by the death glitch and digital-rain atmosphere.
/// * **Safe placement** — the line is rendered in a reserved *lower band*,
///   camera-anchored, that never collides with the top-LEFT TITLE card, the
///   top-RIGHT PAUSE square, or the upper-center discovery/instruction panels.
/// * **Auto-fade** — lines time themselves out; the caller doesn't manage
///   lifetime. Re-presenting replaces the previous line cleanly.
/// * **Accessibility** — when `UIAccessibility.isReduceMotionEnabled` is on, the
///   glitch/typewriter animation is skipped in favor of a calm fade-in, and the
///   text is posted to VoiceOver as an announcement.
///
/// ## Adopting it in a level (replacing ad-hoc commentary labels)
///
/// **Before** — scattered, bare, easy to miss, hand-placed:
/// ```swift
/// let label = SKLabelNode(text: "I see you.")
/// label.fontName = "Menlo"
/// label.fontSize = 8                       // too small to read
/// label.fontColor = strokeColor
/// label.alpha = 0.5                        // half-faded
/// label.position = CGPoint(x: 0, y: 45)    // ad-hoc, may collide with HUD
/// addChild(label)
/// // ...and you own the fade-out timer too.
/// ```
///
/// **After** — one call, consistent voice, safe placement, auto-fade:
/// ```swift
/// GlitchedNarrator.present("I see you.", in: self, style: .whisper)
/// ```
///
/// Pick the `Style` that matches the dramatic weight:
/// ```swift
/// GlitchedNarrator.present("you weren't supposed to find that.", in: self, style: .whisper)
/// GlitchedNarrator.present("INTEGRITY CHECK FAILED", in: self, style: .alert)
/// GlitchedNarrator.present("I AM THE LEVEL NOW.", in: self, style: .boss)
/// ```
///
/// To clear a persistent line early (e.g. on level success), call
/// `GlitchedNarrator.dismiss(in:)`.
///
/// `present(_:in:style:)` is safe to call from `SKScene` subclasses generally;
/// it only requires `SKScene` + `VisualConstants` and reads `ProgressManager`
/// indirectly via the system Reduce-Motion flag — no `BaseLevelScene`-specific
/// API is needed, so non-level scenes (boot, finale) can use it too.
enum GlitchedNarrator {

    // MARK: - Style

    /// The narrator's register. Drives color, size, reveal cadence, and how
    /// long the line lingers before auto-fading.
    enum Style {
        /// Low, intimate aside. Secondary font, accent (cyan), quick gentle
        /// reveal. For "the OS noticed you" moments.
        case whisper
        /// System warning / taunt. Bold font, amber, punchier reveal. For
        /// "something is wrong" beats.
        case alert
        /// Full antagonist declaration. Bold font, danger red, slow heavy
        /// reveal with the strongest glitch. For boss / finale moments.
        case boss

        var fontName: String {
            switch self {
            case .whisper: return VisualConstants.Fonts.secondary
            case .alert, .boss: return VisualConstants.Fonts.main
            }
        }

        /// Readable size floor (vs the audited 8pt). Scaled up for narrow
        /// canvases is unnecessary; these sit comfortably on iPhone 390-wide.
        var fontSize: CGFloat {
            switch self {
            case .whisper: return 16
            case .alert: return 20
            case .boss: return 28
            }
        }

        var color: SKColor {
            switch self {
            case .whisper: return VisualConstants.Colors.accent
            case .alert: return VisualConstants.Colors.warning
            case .boss: return VisualConstants.Colors.danger
            }
        }

        /// Seconds between each character being typed on.
        var perCharacterDelay: TimeInterval {
            switch self {
            case .whisper: return 0.022
            case .alert: return 0.030
            case .boss: return 0.045
            }
        }

        /// How long the fully-revealed line holds before fading out. Longer for
        /// heavier lines so the player can actually read the boss talking.
        var holdDuration: TimeInterval {
            switch self {
            case .whisper: return 2.6
            case .alert: return 3.2
            case .boss: return 4.0
            }
        }

        /// Magnitude (in points) of the RGB-split offset for the chromatic ghost
        /// layers. Bigger = more "corrupted". Zero-equivalent when reduce-motion.
        var rgbSplitOffset: CGFloat {
            switch self {
            case .whisper: return 1.5
            case .alert: return 2.5
            case .boss: return 4.0
            }
        }
    }

    // MARK: - Layout

    /// All narrator nodes live under one named container so a new line cleanly
    /// replaces the old one and `dismiss(in:)` can find them. Parked on the
    /// camera (when present) so the line tracks the visible viewport.
    private static let containerName = "GlitchedNarrator.line"

    /// Draw above gameplay and the difficulty-hint banner (z 8000) but below
    /// full-screen death/transition juice (z 10000+), so the narrator reads
    /// clearly without fighting the victory/death overlays.
    private static let zPosition: CGFloat = 8600

    /// Fraction of the scene height, measured up from the bottom safe edge,
    /// where the narrator band sits. This keeps the line in the LOWER-CENTER
    /// reserved band — clear of:
    ///   * the top-LEFT TITLE card (`HUDZones.titleLeadingInset` column, top),
    ///   * the top-RIGHT PAUSE square (`HUDZones.pauseReservedZone`, top),
    ///   * upper-center discovery / instruction panels (which the title-zone
    ///     comments document as living in the centered top band).
    /// Lower-center is the one wide horizontal strip none of those reserve.
    private static let bandHeightFraction: CGFloat = 0.26

    // MARK: - Public API

    /// Present a 4th-wall narrator line in `scene`.
    ///
    /// Renders a glitch/typewriter reveal in the reserved lower-center band,
    /// holds, then auto-fades. Any line already on screen is replaced. When
    /// system Reduce Motion is enabled, the glitch+typewriter is skipped in
    /// favor of a calm fade-in (and the text is announced to VoiceOver).
    ///
    /// - Parameters:
    ///   - text: The line the OS speaks. Multi-word lines wrap to fit the band
    ///     width; keep them punchy (one to two short sentences).
    ///   - scene: The presenting scene. Camera-anchored when `scene.camera`
    ///     exists, otherwise pinned to the scene's lower-center.
    ///   - style: The narrator register. See `Style`.
    static func present(_ text: String, in scene: SKScene, style: Style = .whisper) {
        // Replace any existing line so the narrator never stacks / overlaps.
        dismiss(in: scene)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let host = anchorNode(in: scene)
        let bandWidth = max(200, scene.size.width - 64)

        let container = SKNode()
        container.name = containerName
        container.zPosition = zPosition
        container.position = bandPosition(in: scene)
        host.addChild(container)

        // The lines of glyphs (wrapped). We build a "main" tinted label per line
        // plus two faint RGB ghost layers behind it for the chromatic split.
        let lines = wrap(trimmed, font: style.fontName, fontSize: style.fontSize, maxWidth: bandWidth)
        let lineHeight = style.fontSize * 1.35
        let totalHeight = CGFloat(lines.count) * lineHeight
        let topY = totalHeight / 2 - lineHeight / 2

        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        var mainLabels: [SKLabelNode] = []
        var ghostLayers: [(node: SKNode, baseOffset: CGFloat)] = []

        for (index, line) in lines.enumerated() {
            let y = topY - CGFloat(index) * lineHeight
            let lineNode = SKNode()
            lineNode.position = CGPoint(x: 0, y: y)
            container.addChild(lineNode)

            if !reduceMotion {
                // RGB split: a red ghost shifted left, a cyan ghost shifted
                // right, behind the true-colored label. This is the same
                // chromatic-aberration language as the death glitch.
                let redGhost = makeLabel(line, style: style, color: SKColor(red: 1, green: 0, blue: 0, alpha: 0.55))
                redGhost.alpha = 0
                redGhost.position = CGPoint(x: -style.rgbSplitOffset, y: 0)
                redGhost.zPosition = -1
                lineNode.addChild(redGhost)
                ghostLayers.append((redGhost, -style.rgbSplitOffset))

                let cyanGhost = makeLabel(line, style: style, color: SKColor(red: 0, green: 1, blue: 1, alpha: 0.55))
                cyanGhost.alpha = 0
                cyanGhost.position = CGPoint(x: style.rgbSplitOffset, y: 0)
                cyanGhost.zPosition = -1
                lineNode.addChild(cyanGhost)
                ghostLayers.append((cyanGhost, style.rgbSplitOffset))
            }

            let main = makeLabel(reduceMotion ? line : "", style: style, color: style.color)
            lineNode.addChild(main)
            mainLabels.append(main)
        }

        if reduceMotion {
            presentReducedMotion(container: container, mainLabels: mainLabels, text: trimmed, style: style)
        } else {
            presentAnimated(
                container: container,
                lines: lines,
                mainLabels: mainLabels,
                ghostLayers: ghostLayers,
                style: style
            )
        }
    }

    /// Remove any narrator line currently presented in `scene` (e.g. on level
    /// success, scene transition, or before showing a new line). No-op if none.
    static func dismiss(in scene: SKScene) {
        for host in [scene.camera, scene].compactMap({ $0 }) {
            host.childNode(withName: containerName)?.removeFromParent()
        }
    }

    // MARK: - Animated (default) presentation

    private static func presentAnimated(
        container: SKNode,
        lines: [String],
        mainLabels: [SKLabelNode],
        ghostLayers: [(node: SKNode, baseOffset: CGFloat)],
        style: Style
    ) {
        // Light glitch punctuation when the line lands — but only via the
        // narrator's own RGB-split flicker, NOT a full-screen effect, so the
        // line stays the focus and we don't fight other juice.
        flickerGhosts(ghostLayers, style: style)

        // Typewriter: reveal each line's characters in sequence, line by line.
        var cumulativeDelay: TimeInterval = 0
        for (lineIndex, line) in lines.enumerated() {
            let mainLabel = mainLabels[lineIndex]
            let characters = Array(line)
            for charIndex in 0...characters.count {
                let revealed = String(characters.prefix(charIndex))
                let delay = cumulativeDelay + Double(charIndex) * style.perCharacterDelay
                mainLabel.run(.sequence([
                    .wait(forDuration: delay),
                    .run { mainLabel.text = revealed }
                ]))
            }
            cumulativeDelay += Double(characters.count + 1) * style.perCharacterDelay
        }

        let revealDuration = cumulativeDelay

        // After the full reveal, hold, then fade the whole container out and
        // remove it. The container owns the lifetime so the caller doesn't.
        container.run(.sequence([
            .wait(forDuration: revealDuration + style.holdDuration),
            .fadeOut(withDuration: 0.45),
            .removeFromParent()
        ]))

        // SFX/haptic punctuation, registered off the audio/haptic managers that
        // already exist; kept lightweight so it reinforces, not overwhelms.
        AudioManager.shared.playClick()
        switch style {
        case .whisper: HapticManager.shared.select()
        case .alert: HapticManager.shared.warning()
        case .boss: HapticManager.shared.warning()
        }
    }

    /// Pulse the RGB ghost layers in/out a couple of times so the line "boots"
    /// with chromatic-aberration energy, then settle them to a faint resting
    /// split that lingers under the main text.
    private static func flickerGhosts(_ ghostLayers: [(node: SKNode, baseOffset: CGFloat)], style: Style) {
        for (ghost, baseOffset) in ghostLayers {
            let jitter = SKAction.sequence([
                .group([.fadeAlpha(to: 0.7, duration: 0.04), .moveTo(x: baseOffset * 2.2, duration: 0.04)]),
                .group([.fadeAlpha(to: 0.2, duration: 0.05), .moveTo(x: baseOffset * 0.6, duration: 0.05)]),
                .group([.fadeAlpha(to: 0.6, duration: 0.04), .moveTo(x: baseOffset * 1.6, duration: 0.04)]),
                .group([.fadeAlpha(to: 0.35, duration: 0.06), .moveTo(x: baseOffset, duration: 0.06)])
            ])
            // Settle to a faint resting split for the hold, then fade with the
            // container's own fade-out.
            ghost.run(.sequence([jitter, .fadeAlpha(to: 0.25, duration: 0.2)]))
        }
    }

    // MARK: - Reduce-Motion presentation

    /// Calm fallback: no typewriter, no RGB split, no flicker. The fully-formed
    /// line fades in, holds, fades out. Also announced to VoiceOver so the
    /// narrator's voice is not motion-gated for assistive-tech users.
    private static func presentReducedMotion(container: SKNode, mainLabels: [SKLabelNode], text: String, style: Style) {
        container.alpha = 0
        container.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: style.holdDuration),
            .fadeOut(withDuration: 0.4),
            .removeFromParent()
        ]))
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    // MARK: - Node construction

    private static func makeLabel(_ text: String, style: Style, color: SKColor) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: style.fontName)
        label.text = text
        label.fontSize = style.fontSize
        label.fontColor = color
        // Full opacity by default — the narrator must be read, not skimmed past.
        label.alpha = 1.0
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

    /// The node the narrator container is parented to. Prefer the camera so the
    /// line stays in the visible viewport even when the camera has panned;
    /// fall back to the scene itself for camera-less scenes.
    private static func anchorNode(in scene: SKScene) -> SKNode {
        scene.camera ?? scene
    }

    /// Position of the band center, in the anchor node's local space.
    ///
    /// When anchored to the camera, local (0,0) is the viewport center, so the
    /// band center is a negative Y offset down into the lower-center strip.
    /// When anchored to the scene (no camera), we use scene coordinates and the
    /// bottom safe inset.
    private static func bandPosition(in scene: SKScene) -> CGPoint {
        let bottomInset = scene.view?.safeAreaInsets.bottom ?? 0
        // Center of the reserved lower band, measured up from the bottom edge.
        let bandCenterFromBottom = max(96, bottomInset + 72) + scene.size.height * bandHeightFraction / 2

        if scene.camera != nil {
            // Camera-local: viewport center is (0,0); push down into lower band.
            let y = -scene.size.height / 2 + bandCenterFromBottom
            return CGPoint(x: 0, y: y)
        } else {
            // Scene-local: absolute lower-center.
            return CGPoint(x: scene.size.width / 2, y: bandCenterFromBottom)
        }
    }

    // MARK: - Text wrapping

    /// Greedy word-wrap so long narrator lines stay inside the band width
    /// instead of clipping off the screen edges. Measures with the actual font
    /// so wrapping is correct for both Menlo and Menlo-Bold at any size.
    private static func wrap(_ text: String, font: String, fontSize: CGFloat, maxWidth: CGFloat) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        let uiFont = UIFont(name: font, size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        func width(_ s: String) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: uiFont]).width
        }

        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if width(candidate) <= maxWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
