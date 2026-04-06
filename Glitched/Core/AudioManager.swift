import AVFoundation
import UIKit

/// Procedural audio synthesis for game sounds.
/// No audio files needed - generates everything in real-time.
final class AudioManager {
    static let shared = AudioManager()

    private var audioEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?

    private var playerPool: [AVAudioPlayerNode] = []
    private let maxPoolSize = 8

    private var ambientPlayers: [AVAudioPlayerNode] = []
    private var activeAmbientIndex = 0
    private var currentAmbientWorld: World?
    private var isAmbientPaused = false

    private var isMuted = false
    private var sfxVolume: Float = 0.7
    private var musicVolume: Float = 0.7

    private init() {
        setupAudioSession()
        setupAudioEngine()
        applySettings(ProgressManager.shared.load().settings)
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
        let engine = AVAudioEngine()
        audioEngine = engine
        mixerNode = engine.mainMixerNode

        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        ambientPlayers = [AVAudioPlayerNode(), AVAudioPlayerNode()]
        for player in ambientPlayers {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
            player.volume = 0
        }

        do {
            try engine.start()
        } catch {
            print("Audio engine error: \(error)")
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            audioEngine?.pause()
        case .ended:
            let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                try? audioEngine?.start()
                if let currentAmbientWorld {
                    playAmbientBed(for: currentAmbientWorld)
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Sound Effects

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
            let envelope = min(1.0, Float(frameCount - UInt32(frame)) / (sampleRate * 0.02))
            let sample = sin(2.0 * .pi * frequency * phase) * volume * envelope * sfxVolume
            channelData?[frame] = sample
        }

        playBuffer(buffer)
    }

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

        var phase: Float = 0
        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let frequency: Float = 300 + progress * 400
            let envelope = 1.0 - progress
            let sample = sin(phase) * 0.25 * envelope * sfxVolume
            phase += (2.0 * .pi * frequency / sampleRate)
            channelData?[frame] = sample
        }

        playBuffer(buffer)
    }

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
            let frequency: Float = 80 - progress * 30
            let phase = Float(frame) / sampleRate
            let envelope = (1.0 - progress) * (1.0 - progress)
            let noise = Float.random(in: -0.1...0.1) * envelope
            let sample = (sin(2.0 * .pi * frequency * phase) * 0.4 + noise) * envelope * intensity * sfxVolume
            channelData?[frame] = sample
        }

        playBuffer(buffer)
    }

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

        var phase: Float = 0
        var harmonicPhase: Float = 0
        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let frequency: Float = 400 * (1.0 - progress * 0.7)

            var sample = sin(phase) * 0.3
            sample += sin(harmonicPhase) * 0.15
            sample += Float.random(in: -0.1...0.1) * (1.0 - progress)

            phase += (2.0 * .pi * frequency / sampleRate)
            harmonicPhase += (2.0 * .pi * frequency * 1.5 / sampleRate)

            let envelope = min(1.0, (1.0 - progress) * 2.0)
            channelData?[frame] = sample * envelope * sfxVolume
        }

        playBuffer(buffer)
    }

    func playVictory() {
        let notes: [Float] = [523.25, 659.25, 783.99, 1046.50]
        let delays: [Double] = [0, 0.1, 0.2, 0.35]

        for (note, delay) in zip(notes, delays) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.playBeep(frequency: note, duration: 0.15, volume: 0.35)
            }
        }
    }

    func playCollect() {
        playBeep(frequency: 1200, duration: 0.06, volume: 0.25)
    }

    func playClick() {
        playBeep(frequency: 600, duration: 0.03, volume: 0.15)
    }

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

        var phase: Float = 0
        var lfoPhaseAccum: Float = 0
        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let frequency: Float = sin(lfoPhaseAccum) > 0 ? 200 : 150
            lfoPhaseAccum += (2.0 * .pi * 8.0 / sampleRate)

            let sample = sin(phase) * 0.3
            phase += (2.0 * .pi * frequency / sampleRate)

            let envelope = sin(.pi * progress)
            channelData?[frame] = sample * envelope * sfxVolume
        }

        playBuffer(buffer)
    }

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

        var phase: Float = 0
        var currentFrequency: Float = Float.random(in: 200...2000)
        var isSineBurst = Int.random(in: 0..<10) < 3
        let burstLength = 64

        for frame in 0..<Int(frameCount) {
            if frame % burstLength == 0 {
                currentFrequency = Float.random(in: 200...2000)
                isSineBurst = Int.random(in: 0..<10) < 3
                phase = 0
            }

            var sample: Float = 0
            if isSineBurst {
                sample = sin(phase) * 0.4
                phase += (2.0 * .pi * currentFrequency / sampleRate)
            } else {
                sample = Float.random(in: -0.3...0.3)
            }

            let envelope = 1.0 - Float(frame) / Float(frameCount)
            channelData?[frame] = sample * envelope * sfxVolume
        }

        playBuffer(buffer)
    }

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

            var sample = sin(2.0 * .pi * 40 * phase) * 0.3
            sample += sin(2.0 * .pi * 60 * phase) * 0.2
            sample += sin(2.0 * .pi * 80 * phase) * 0.1
            sample += Float.random(in: -0.1...0.1)

            channelData?[frame] = sample * intensity * sfxVolume * 0.5
        }

        playBuffer(buffer)
    }

    func playCountdownTick(isLast: Bool = false) {
        if isLast {
            playBeep(frequency: 880, duration: 0.2, volume: 0.4)
        } else {
            playBeep(frequency: 440, duration: 0.1, volume: 0.3)
        }
    }

    // MARK: - Ambient Beds

    func playAmbientBed(for world: World) {
        guard world != .world0, let engine = audioEngine else {
            stopAmbientBed()
            return
        }

        if currentAmbientWorld == world, ambientPlayers[activeAmbientIndex].isPlaying {
            applyAmbientVolume()
            return
        }

        let nextIndex = activeAmbientIndex == 0 ? 1 : 0
        let nextPlayer = ambientPlayers[nextIndex]
        let previousPlayer = ambientPlayers[activeAmbientIndex]
        let format = engine.mainMixerNode.outputFormat(forBus: 0)

        nextPlayer.stop()
        nextPlayer.reset()
        nextPlayer.volume = 0

        guard let buffer = makeAmbientBuffer(for: world, format: format, duration: 8.0) else { return }
        nextPlayer.scheduleBuffer(buffer, at: nil, options: [.loops])
        nextPlayer.play()

        rampVolume(for: nextPlayer, to: musicVolume, duration: 0.8)
        rampVolume(for: previousPlayer, to: 0, duration: 0.8) { [weak previousPlayer] in
            previousPlayer?.stop()
        }

        activeAmbientIndex = nextIndex
        currentAmbientWorld = world
        isAmbientPaused = false
    }

    func pauseAmbientBed() {
        guard !isAmbientPaused else { return }
        ambientPlayers[activeAmbientIndex].pause()
        isAmbientPaused = true
    }

    func resumeAmbientBed() {
        guard isAmbientPaused else { return }
        ambientPlayers[activeAmbientIndex].play()
        applyAmbientVolume()
        isAmbientPaused = false
    }

    func stopAmbientBed(fadeDuration: TimeInterval = 0.4) {
        for player in ambientPlayers {
            rampVolume(for: player, to: 0, duration: fadeDuration) { [weak player] in
                player?.stop()
            }
        }
        currentAmbientWorld = nil
        isAmbientPaused = false
    }

    private func makeAmbientBuffer(for world: World, format: AVAudioFormat, duration: Float) -> AVAudioPCMBuffer? {
        let sampleRate = Float(format.sampleRate)
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let channelCount = Int(format.channelCount)
        for frame in 0..<Int(frameCount) {
            let t = Float(frame) / sampleRate
            let normalizedTime = t / duration
            let sample = ambientSample(for: world, t: t, normalizedTime: normalizedTime)
            for channel in 0..<channelCount {
                buffer.floatChannelData?[channel][frame] = sample
            }
        }

        return buffer
    }

    private func ambientSample(for world: World, t: Float, normalizedTime: Float) -> Float {
        let loop = normalizedTime * 2.0 * .pi
        let drone = sin(loop)
        let shimmer = sin(loop * 2.0)
        let noise = sin(loop * 17.0 + 0.3) * sin(loop * 11.0 + 0.9)

        switch world {
        case .world1:
            let hum = sin(2.0 * .pi * 48 * t) * 0.14 + sin(2.0 * .pi * 96 * t) * 0.05
            let beeps = max(0, sin(loop * 4.0)) * sin(2.0 * .pi * 880 * t) * 0.025
            return hum + beeps + noise * 0.01
        case .world2:
            let bed = sin(2.0 * .pi * 140 * t + drone * 0.4) * 0.05
            let chirp = max(0, sin(loop * 6.0)) * sin(2.0 * .pi * (420 + shimmer * 120) * t) * 0.05
            let transfer = sin(2.0 * .pi * 36 * t) * 0.03
            return bed + chirp + transfer + noise * 0.015
        case .world3:
            let bass = sin(2.0 * .pi * 42 * t) * 0.18
            let distortion = tanh(Float(Double(bass + noise * 0.05) * 2.3)) * 0.35
            let crackle = max(0, sin(loop * 13.0)) * noise * 0.06
            return distortion + crackle
        case .world4:
            let pad = sin(2.0 * .pi * 110 * t + drone * 0.9) * 0.08
            let fifth = sin(2.0 * .pi * 165 * t + shimmer * 0.6) * 0.05
            let sweep = sin(loop * 1.5) * sin(2.0 * .pi * 520 * t) * 0.03
            return pad + fifth + sweep + noise * 0.01
        case .world5:
            let alarm = (sin(loop * 2.0) > 0 ? 1.0 : -1.0) * sin(2.0 * .pi * 82 * t) * 0.12
            let warning = max(0, sin(loop * 4.0)) * sin(2.0 * .pi * 660 * t) * 0.05
            let bars = sin(loop * 9.0) * 0.03
            return alarm + warning + bars + noise * 0.02
        case .world0:
            return 0
        }
    }

    private func rampVolume(for player: AVAudioPlayerNode, to target: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let startVolume = player.volume
        let steps = max(1, Int(duration / 0.05))

        for step in 1...steps {
            let progress = Float(step) / Float(steps)
            let value = startVolume + (target - startVolume) * progress
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(step) / Double(steps)) {
                player.volume = value
                if step == steps {
                    completion?()
                }
            }
        }
    }

    private func applyAmbientVolume() {
        ambientPlayers[activeAmbientIndex].volume = musicVolume
    }

    // MARK: - Helper

    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let engine = audioEngine else { return }

        let playerNode: AVAudioPlayerNode
        if let idleNode = playerPool.first(where: { !$0.isPlaying }) {
            playerNode = idleNode
        } else if playerPool.count < maxPoolSize {
            let newNode = AVAudioPlayerNode()
            engine.attach(newNode)
            engine.connect(newNode, to: engine.mainMixerNode, format: buffer.format)
            playerPool.append(newNode)
            playerNode = newNode
        } else {
            playerNode = playerPool[0]
            playerNode.stop()
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()
    }

    // MARK: - Controls

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    func setVolume(_ volume: Float) {
        setSFXVolume(volume)
    }

    func setMusicVolume(_ volume: Float) {
        musicVolume = max(0, min(1, volume))
        applyAmbientVolume()
    }

    func setSFXVolume(_ volume: Float) {
        sfxVolume = max(0, min(1, volume))
    }

    func applySettings(_ settings: PlayerSettings) {
        setMusicVolume(settings.musicVolume)
        setSFXVolume(settings.sfxVolume)
    }
}
