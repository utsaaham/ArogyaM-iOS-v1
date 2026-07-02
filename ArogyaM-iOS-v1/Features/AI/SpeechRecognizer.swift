import Foundation
import Combine
import Speech
import AVFoundation

/// Live dictation for the AI composer. Tap the mic to start, tap again to stop;
/// partial results stream into `transcript` so the text field updates as you talk.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var permissionDenied = false

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard recognizer?.isAvailable == true else { return }
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.permissionDenied = true
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.permissionDenied = true
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }

    private func beginSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            // Capture `request` directly: the tap fires on an audio thread.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer?.recognitionTask(with: request) { result, error in
                Task { @MainActor in
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                    }
                }
            }
        } catch {
            stop()
        }
    }
}
