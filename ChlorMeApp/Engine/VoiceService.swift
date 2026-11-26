import Foundation
import AVFoundation
import Speech
import SwiftUI

/// Provides on-device Text-to-Speech (AVSpeechSynthesizer) and Speech-to-Text dictation (SFSpeechRecognizer).
@MainActor
public final class VoiceService: NSObject, ObservableObject {
    @Published public var isSpeaking: Bool = false
    @Published public var speakingMessageId: String?
    @Published public var isRecording: Bool = false
    @Published public var recognizedText: String = ""
    @Published public var voiceError: String?

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public static func availableChineseVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("zh") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    public func speak(
        text: String,
        messageId: String?,
        voiceIdentifier: String?,
        rate: Double = 0.50,
        pitch: Double = 1.05
    ) {
        if isSpeaking && speakingMessageId == messageId && messageId != nil {
            stopSpeaking()
            return
        }
        stopSpeaking()

        // Strip markdown action asterisks before speaking so it sounds natural
        let cleaned = text
            .replacingOccurrences(of: #"\*[^*]+\*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: cleaned)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        utterance.rate = Float(max(0.30, min(0.65, rate)))
        utterance.pitchMultiplier = Float(max(0.75, min(1.35, pitch)))
        utterance.preUtteranceDelay = 0.05

        speakingMessageId = messageId
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    public func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        speakingMessageId = nil
    }

    // MARK: - Live Speech-to-Text Dictation

    public func toggleDictation(onUpdate: @escaping (String) -> Void) {
        if isRecording {
            stopDictation()
        } else {
            Task { await startDictation(onUpdate: onUpdate) }
        }
    }

    private func startDictation(onUpdate: @escaping (String) -> Void) async {
        stopSpeaking()
        voiceError = nil

        let speechAllowed = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else {
            voiceError = "请在系统设置中开启语音识别权限"
            return
        }

        let micAllowed = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micAllowed else {
            voiceError = "请在系统设置中开启麦克风权限"
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            voiceError = "当前设备语音识别暂不可用"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            recognizedText = ""

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.recognizedText = text
                        onUpdate(text)
                        if result.isFinal {
                            self.stopDictation()
                        }
                    } else if error != nil {
                        self.stopDictation()
                    }
                }
            }
        } catch {
            voiceError = "语音听写启动失败：\(error.localizedDescription)"
            stopDictation()
        }
    }

    public func stopDictation() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}

extension VoiceService: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingMessageId = nil
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingMessageId = nil
        }
    }
}
