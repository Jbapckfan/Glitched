import AVFoundation
import UIKit

/// Procedural audio synthesis for game sounds
/// No audio files needed - generates everything in real-time
final class AudioManager {
    static let shared = AudioManager()

    private var audioEngine: AVAudioEngine?
    private var playerNodes: [String: AVAudioPlayerNode] = [:]
    private var mixerNode: AVAudioMixerNode?

    private var isMuted = false
    private var masterVolume: Float = 0.7

    private init() {
        setupAudioSession()
        setupAudioEngine()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        mixerNode = audioEngine?.mainMixerNode

        do {
            try audioEngine?.start()
        } catch {
            print("Audio engine error: \(error)")
        }
    }

    // MARK: - Sound Effects

    /// Play a synthesized beep/blip sound
    func playBeep(frequency: Float = 880, duration: Float = 0.1, volume: Float = 0.3) {
        guard !isMuted, let engine = audioEngine else { return }

        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.mainMixerNode.outputFormat(forBus: 0),
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount

        let channelData = buffer.floatChannelData?[0]

        for frame in 0..<Int(frameCount) {
            let phase = Float(frame) / sampleRate
            let envelope = min(1.0, Float(frameCount - UInt32(frame)) / (sampleRate * 0.02)) // Quick decay
            let sample = sin(2.0 * .pi * frequency * phase) * volume * envelope * masterVolume
            channelData?[frame] = sample
        }

        playBuffer(buffer)
    }

    /// Jump sound - quick rising tone
    func playJump() {
        guard !isMuted, let engine = audioEngine else { return }

        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let duration: Float = 0.12
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.mainMixerNode.outputFormat(forBus: 0),
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData?[0]

        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let frequency: Float = 300 + progress * 400 // Rising pitch
            let phase = Float(frame) / sampleRate
            let envelope = 1.0 - progress // Fade out
            let sample = sin(2.0 * .pi * frequency * phase) * 0.25 * envelope * masterVolume
            channelData?[frame] = sample
        }

        playBuffer(buffer)
    }

    /// Land sound - thud
    func playLand(intensity: Float = 1.0) {
        guard !isMuted, let engine = audioEngine else { return }

        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let duration: Float = 0.08
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.mainMixerNode.outputFormat(forBus: 0),
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData?[0]

        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let frequency: Float = 80 - progress * 30 // Low descending
            let phase = Float(frame) / sampleRate
            let envelope = (1.0 - progress) * (1.0 - progress) // Quick decay
            let noise = Float.random(in: -0.1...0.1) * envelope
            let sample = (sin(2.0 * .pi * frequency * phase) * 0.4 + noise) * envelope * intensity * masterVolume
            channelData?[frame] = sample
        }

        playBuffer(buffer)
    }

    /// Death sound - descending glitchy buzz
    func playDeath() {
        guard !isMuted, let engine = audioEngine else { return }

        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let duration: Float = 0.5
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.mainMixerNode.outputFormat(forBus: 0),
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData?[0]

        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let frequency: Float = 400 * (1.0 - progress * 0.7) // Descending
            let phase = Float(frame) / sampleRate

            // Add some harmonics and noise for "glitchy" feel
            var sample = sin(2.0 * .pi * frequency * phase) * 0.3
            sample += sin(2.0 * .pi * frequency * 1.5 * phase) * 0.15
            sample += Float.random(in: -0.1...0.1) * (1.0 - progress)

            let envelope = min(1.0, (1.0 - progress) * 2.0)
            channelData?[frame] = sample * envelope * masterVolume
        }

        playBuffer(buffer)
    }

    /// Victory fanfare - ascending arpeggio
    func playVictory() {
        let notes: [Float] = [523.25, 659.25, 783.99, 1046.50] // C5, E5, G5, C6
        let delays: [Double] = [0, 0.1, 0.2, 0.35]

        for (note, delay) in zip(notes, delays) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.playBeep(frequency: note, duration: 0.15, volume: 0.35)
            }
        }
    }

    /// Collect item - quick high blip
    func playCollect() {
        playBeep(frequency: 1200, duration: 0.06, volume: 0.25)
    }

    /// Button press - soft click
    func playClick() {
        playBeep(frequency: 600, duration: 0.03, volume: 0.15)
    }

    /// Danger warning - low pulsing
    func playDanger() {
        guard !isMuted, let engine = audioEngine else { return }

        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let duration: Float = 0.3
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.mainMixerNode.outputFormat(forBus: 0),
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData?[0]

        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let phase = Float(frame) / sampleRate

            // Two-tone alternating
            let freq1: Float = 200
            let freq2: Float = 150
            let lfoPhase = sin(2.0 * .pi * 8.0 * phase)
            let frequency = lfoPhase > 0 ? freq1 : freq2

            let sample = sin(2.0 * .pi * frequency * phase) * 0.3
            let envelope = sin(.pi * progress) // Fade in and out
            channelData?[frame] = sample * envelope * masterVolume
        }

        playBuffer(buffer)
    }

    /// Glitch sound effect
    func playGlitch() {
        guard !isMuted, let engine = audioEngine else { return }

        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let duration: Float = 0.15
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.mainMixerNode.outputFormat(forBus: 0),
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData?[0]

        for frame in 0..<Int(frameCount) {
            // Digital noise with occasional sine bursts
            var sample: Float = 0

            if Int.random(in: 0..<10) < 3 {
                // Sine burst
                let phase = Float(frame) / sampleRate
                sample = sin(2.0 * .pi * Float.random(in: 200...2000) * phase) * 0.4
            } else {
                // Noise
                sample = Float.random(in: -0.3...0.3)
            }

            let envelope = 1.0 - Float(frame) / Float(frameCount)
            channelData?[frame] = sample * envelope * masterVolume
        }

        playBuffer(buffer)
    }

    /// Crusher rumble - continuous low drone
    func playCrusherRumble(intensity: Float) {
        guard !isMuted, let engine = audioEngine else { return }

        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let duration: Float = 0.1
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.mainMixerNode.outputFormat(forBus: 0),
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData?[0]

        for frame in 0..<Int(frameCount) {
            let phase = Float(frame) / sampleRate

            // Low rumble with harmonics
            var sample = sin(2.0 * .pi * 40 * phase) * 0.3
            sample += sin(2.0 * .pi * 60 * phase) * 0.2
            sample += sin(2.0 * .pi * 80 * phase) * 0.1
            sample += Float.random(in: -0.1...0.1) // Noise

            channelData?[frame] = sample * intensity * masterVolume * 0.5
        }

        playBuffer(buffer)
    }

    /// Countdown tick
    func playCountdownTick(isLast: Bool = false) {
        if isLast {
            playBeep(frequency: 880, duration: 0.2, volume: 0.4)
        } else {
            playBeep(frequency: 440, duration: 0.1, volume: 0.3)
        }
    }

    // MARK: - Helper

    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let engine = audioEngine else { return }

        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) {
            DispatchQueue.main.async {
                engine.detach(playerNode)
            }
        }

        playerNode.play()
    }

    // MARK: - Controls

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    func setVolume(_ volume: Float) {
        masterVolume = max(0, min(1, volume))
    }
}
