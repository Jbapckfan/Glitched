import UIKit
import Speech
import Combine

/// Manages speech recognition for voice command gameplay
final class VoiceCommandManager: DeviceManager {
    static let shared = VoiceCommandManager()

    let supportedMechanics: Set<MechanicType> = [.voiceCommand]

    private var isActive = false
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            DispatchQueue.main.async {
                self?.startListening()
            }
        }

        print("VoiceCommandManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        stopListening()
        print("VoiceCommandManager: Deactivated")
    }

    private func startListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let result = result else { return }

            let text = result.bestTranscription.formattedString.uppercased()
            let words = text.split(separator: " ").map(String.init)

            // Check for recognized commands
            let commands = ["OPEN", "FLY", "JUMP", "HELP", "STOP", "GO", "BRIDGE", "UNLOCK"]
            for command in commands {
                if let lastWord = words.last, lastWord == command {
                    DispatchQueue.main.async {
                        InputEventBus.shared.post(.voiceCommandRecognized(command: command))
                    }
                    break
                }
            }

            if error != nil || result.isFinal {
                self?.stopListening()
                if self?.isActive == true {
                    // Restart after a brief pause
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.startListening()
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("VoiceCommandManager: Failed to start audio engine: \(error)")
        }
    }

    private func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
    }
}
