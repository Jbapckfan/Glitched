import AVFoundation
import Combine

extension Notification.Name {
    static let envPermissionDenied = Notification.Name("envPermissionDenied")
}

final class MicrophoneManager: DeviceManager {
    static let shared = MicrophoneManager()

    let supportedMechanics: Set<MechanicType> = [.microphone]

    private let engine = AVAudioEngine()
    private var isRunning = false
    private var wantsCapture = false

    private init() {}

    func activate() {
        wantsCapture = true
        guard !isRunning else { return }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.wantsCapture else { return }
                if granted {
                    self.startCapture()
                } else {
                    AccessibilityManager.shared.forceHardwareFallback(for: .microphone)
                    NotificationCenter.default.post(name: .envPermissionDenied, object: nil)
                }
            }
        }
    }

    func deactivate() {
        wantsCapture = false
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        // Hand the shared AVAudioSession back to AudioManager (the playback owner)
        // instead of calling setActive(false). Deactivating here would leave the
        // process-wide session inactive and stuck in the .record category, which
        // silences ALL game audio (ambient + SFX + UI) for the rest of the run —
        // AudioManager only re-asserts the session on an interruption .ended event,
        // and a programmatic setActive(false) posts no such notification.
        AudioManager.shared.restorePlaybackSession()
    }

    private func startCapture() {
        guard wantsCapture else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)

            guard format.sampleRate > 0, format.channelCount > 0 else {
                print("MicrophoneManager: Invalid audio format")
                AccessibilityManager.shared.forceHardwareFallback(for: .microphone)
                return
            }

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }

            engine.prepare()
            try engine.start()
            isRunning = true
            print("MicrophoneManager: Started audio capture")
        } catch {
            print("MicrophoneManager error: \(error)")
            AccessibilityManager.shared.forceHardwareFallback(for: .microphone)
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        for i in 0..<count {
            sum += samples[i] * samples[i]
        }
        let rms = sqrtf(sum / Float(count))

        // Normalize and scale for game use (adjust multiplier as needed)
        let normalized = min(max(rms * 15, 0), 1)

        DispatchQueue.main.async {
            InputEventBus.shared.post(.micLevelChanged(power: normalized))
        }
    }
}
