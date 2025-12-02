import AVFoundation
import Combine

extension Notification.Name {
    static let micPermissionDenied = Notification.Name("micPermissionDenied")
}

final class MicrophoneManager: DeviceManager {
    static let shared = MicrophoneManager()

    let supportedMechanics: Set<MechanicType> = [.microphone]

    private let engine = AVAudioEngine()
    private var isRunning = false

    private init() {}

    func activate() {
        guard !isRunning else { return }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.startCapture()
                } else {
                    AccessibilityManager.shared.forceHardwareFallback(for: .microphone)
                    NotificationCenter.default.post(name: .micPermissionDenied, object: nil)
                }
            }
        }
    }

    func deactivate() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        isRunning = false
    }

    private func startCapture() {
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
