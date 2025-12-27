import UIKit
import CoreHaptics

/// Rich haptic feedback that makes every action FEEL powerful
final class HapticManager {
    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool = false

    // Pre-created generators for quick access
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        setupHaptics()
        prepareGenerators()
    }

    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        supportsHaptics = true

        do {
            engine = try CHHapticEngine()
            try engine?.start()

            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }

            engine?.stoppedHandler = { reason in
                print("Haptic engine stopped: \(reason)")
            }
        } catch {
            print("Haptic engine error: \(error)")
        }
    }

    private func prepareGenerators() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        impactRigid.prepare()
        impactSoft.prepare()
        selection.prepare()
        notification.prepare()
    }

    // MARK: - Basic Haptics

    func light() {
        impactLight.impactOccurred()
    }

    func medium() {
        impactMedium.impactOccurred()
    }

    func heavy() {
        impactHeavy.impactOccurred()
    }

    func rigid() {
        impactRigid.impactOccurred()
    }

    func soft() {
        impactSoft.impactOccurred()
    }

    func select() {
        selection.selectionChanged()
    }

    func success() {
        notification.notificationOccurred(.success)
    }

    func warning() {
        notification.notificationOccurred(.warning)
    }

    func error() {
        notification.notificationOccurred(.error)
    }

    // MARK: - Game-Specific Haptics

    /// Player jumps
    func jump() {
        impactMedium.impactOccurred(intensity: 0.7)
    }

    /// Player lands
    func land(velocity: CGFloat) {
        let intensity = min(1.0, abs(velocity) / 500)
        if intensity > 0.7 {
            impactHeavy.impactOccurred(intensity: intensity)
        } else if intensity > 0.3 {
            impactMedium.impactOccurred(intensity: intensity)
        } else {
            impactLight.impactOccurred(intensity: intensity)
        }
    }

    /// Player dies - dramatic buzz
    func death() {
        playPattern(.death)
    }

    /// Level complete - celebration
    func victory() {
        playPattern(.victory)
    }

    /// Collecting item
    func collect() {
        impactRigid.impactOccurred(intensity: 0.5)
    }

    /// Button press
    func buttonPress() {
        impactLight.impactOccurred(intensity: 0.6)
    }

    /// Danger warning
    func dangerPulse() {
        playPattern(.danger)
    }

    /// Crusher approaching
    func crusherRumble(intensity: CGFloat) {
        guard supportsHaptics, let engine = engine else {
            impactHeavy.impactOccurred(intensity: intensity)
            return
        }

        do {
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity))

            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [sharpness, intensityParam],
                relativeTime: 0,
                duration: 0.1
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            impactHeavy.impactOccurred(intensity: intensity)
        }
    }

    /// Heartbeat for tense moments
    func heartbeat() {
        playPattern(.heartbeat)
    }

    /// Glitch effect
    func glitch() {
        playPattern(.glitch)
    }

    // MARK: - Custom Patterns

    enum HapticPattern {
        case death
        case victory
        case danger
        case heartbeat
        case glitch
        case countdown
    }

    func playPattern(_ pattern: HapticPattern) {
        guard supportsHaptics, let engine = engine else {
            // Fallback
            switch pattern {
            case .death: error()
            case .victory: success()
            case .danger: warning()
            case .heartbeat: heavy()
            case .glitch: rigid()
            case .countdown: medium()
            }
            return
        }

        do {
            let hapticPattern = try createPattern(pattern)
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }

    private func createPattern(_ pattern: HapticPattern) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []

        switch pattern {
        case .death:
            // Descending buzz
            for i in 0..<5 {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0 - Float(i) * 0.15)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: Double(i) * 0.08
                ))
            }

        case .victory:
            // Ascending celebration
            let times = [0.0, 0.1, 0.2, 0.35, 0.5]
            let intensities: [Float] = [0.5, 0.6, 0.7, 0.85, 1.0]
            for (time, intensity) in zip(times, intensities) {
                let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensityParam, sharpness],
                    relativeTime: time
                ))
            }

        case .danger:
            // Quick double tap
            for i in 0..<2 {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: Double(i) * 0.12
                ))
            }

        case .heartbeat:
            // Lub-dub
            let times = [0.0, 0.15, 0.6, 0.75]
            let intensities: [Float] = [0.8, 0.5, 0.8, 0.5]
            for (time, intensity) in zip(times, intensities) {
                let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensityParam, sharpness],
                    relativeTime: time
                ))
            }

        case .glitch:
            // Random bursts
            for i in 0..<8 {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float.random(in: 0.3...1.0))
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float.random(in: 0.5...1.0))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: Double(i) * Double.random(in: 0.02...0.05)
                ))
            }

        case .countdown:
            // Single strong tap
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: 0
            ))
        }

        return try CHHapticPattern(events: events, parameters: [])
    }

    // MARK: - Continuous Haptics

    private var continuousPlayer: CHHapticAdvancedPatternPlayer?

    func startContinuousRumble(intensity: Float = 0.5, sharpness: Float = 0.3) {
        guard supportsHaptics, let engine = engine else { return }

        do {
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)

            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: 0,
                duration: 100
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            continuousPlayer = try engine.makeAdvancedPlayer(with: pattern)
            try continuousPlayer?.start(atTime: 0)
        } catch {
            print("Failed to start continuous haptic: \(error)")
        }
    }

    func updateContinuousRumble(intensity: Float) {
        guard let player = continuousPlayer else { return }

        do {
            let intensityParam = CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: intensity,
                relativeTime: 0
            )
            try player.sendParameters([intensityParam], atTime: 0)
        } catch {
            print("Failed to update haptic: \(error)")
        }
    }

    func stopContinuousRumble() {
        try? continuousPlayer?.stop(atTime: 0)
        continuousPlayer = nil
    }
}
