import AVFoundation
import Speech
import TalkCore

@MainActor
final class AudioCapture {
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var sessionID = UUID()
    private var tapInstalled = false
    private var finalReceived = false
    private var recognitionError: Error?
    private var text = ""
    private var sink: AudioSink?
    private var directory: URL?
    var onTranscript: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFailure: ((Error) -> Void)?
    var usedPartialTranscript: Bool { !finalReceived || recognitionError != nil }

    static func cleanAbandonedAudio() {
        let root = FileManager.default.temporaryDirectory
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for folder in folders where folder.lastPathComponent.hasPrefix("HydayTalk-") {
            let parts = folder.lastPathComponent.dropFirst("HydayTalk-".count).split(separator: "-", maxSplits: 1)
            guard parts.count == 2, let processID = Int32(parts[0]), processID > 0,
                  UUID(uuidString: String(parts[1])) != nil,
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            if kill(processID, 0) == -1 && errno == ESRCH { try? FileManager.default.removeItem(at: folder) }
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func start(settings: TalkSettings, hints: [String]) throws {
        cancel(); engine = AVAudioEngine(); sessionID = UUID()
        let current = sessionID; text = ""; finalReceived = false; recognitionError = nil
        if settings.speechBackend == .system {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: settings.locale)), recognizer.isAvailable else {
                throw TalkError("系統語音辨識暫時無法使用。請確認網路，或切換辨識來源。")
            }
            if settings.systemOfflineOnly && !recognizer.supportsOnDeviceRecognition {
                throw TalkError("這台 Mac 的系統辨識不支援目前語言離線使用。請關閉「僅使用離線辨識」或選擇本機模型。")
            }
            let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
            bufferRequest.shouldReportPartialResults = true
            bufferRequest.requiresOnDeviceRecognition = settings.systemOfflineOnly
            bufferRequest.addsPunctuation = true
            bufferRequest.contextualStrings = hints
            request = bufferRequest
            recognition = recognizer.recognitionTask(with: bufferRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.sessionID == current else { return }
                    if let result {
                        self.text = result.bestTranscription.formattedString
                        self.onTranscript?(self.text)
                        self.finalReceived = result.isFinal
                    }
                    if let error {
                        self.recognitionError = error; self.finalReceived = true
                        if self.engine.isRunning { self.onFailure?(TalkError("系統辨識已中斷。請確認網路後重試，或切換辨識來源。")) }
                    } else if result?.isFinal == true, self.engine.isRunning {
                        self.onFailure?(TalkError("系統辨識已結束，請完成這次錄音。"))
                    }
                }
            }
        }
        // Every backend writes the audio, so a failed transcription can be retried from it.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HydayTalk-\(getpid())-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        directory = folder
        let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
        MeterDiagnostics.shared.start(sampleRate: format.sampleRate, channels: format.channelCount)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            cancel(); throw TalkError("找不到麥克風。請在「系統設定 → 聲音 → 輸入」選擇麥克風。")
        }
        let file: AVAudioFile?
        do {
            var fileSettings = format.settings
            fileSettings.removeValue(forKey: AVLinearPCMIsNonInterleaved)
            file = try directory.map { try AVAudioFile(forWriting: $0.appendingPathComponent("capture.caf"), settings: fileSettings) }
        } catch { cancel(); throw TalkError("無法建立暫存錄音。請確認磁碟空間。") }
        let audioSink = AudioSink(request: request, file: file)
        sink = audioSink
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            audioSink.append(buffer)
            let level = Self.level(buffer)
            Task { @MainActor in
                guard let self, self.sessionID == current else { return }
                self.onLevel?(level)
            }
        }
        tapInstalled = true; engine.prepare()
        do { try engine.start() } catch { cancel(); throw TalkError("無法啟動麥克風。請確認麥克風權限與輸入裝置。") }
    }

    private nonisolated static func level(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = sqrt(Double(sum) / Double(buffer.frameLength))
        return min(1, max(0, (20 * log10(max(rms, 0.00001)) + 55) / 55))
    }

    func stop() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        sink?.close(); request?.endAudio()
    }

    func systemTranscript() async throws -> String {
        for _ in 0..<80 {
            if finalReceived { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        recognition?.cancel(); recognition = nil; request = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TalkError(recognitionError == nil ? "沒有辨識到文字。請確認麥克風後再試一次。" : "系統辨識沒有回傳文字。請確認網路後重試。")
        }
        return text
    }

    func audioFile() async throws -> URL {
        guard let directory else { throw TalkError("找不到這次錄音。請重新錄音。") }
        if sink?.writeFailed == true { throw TalkError("錄音寫入失敗。請確認磁碟空間後重試。") }
        let output = directory.appendingPathComponent("dictation.wav")
        try await SpeechTranscription.normalize(source: directory.appendingPathComponent("capture.caf"), output: output)
        return output
    }

    /// Transcribes a saved recording with the system recognizer, for retries.
    static func systemTranscript(of file: URL, settings: TalkSettings, hints: [String]) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: settings.locale)), recognizer.isAvailable else {
            throw TalkError("系統語音辨識暫時無法使用。請確認網路，或切換辨識來源。")
        }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.requiresOnDeviceRecognition = settings.systemOfflineOnly
        request.addsPunctuation = true
        request.contextualStrings = hints
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let error { finished = true; continuation.resume(throwing: TalkError("系統辨識失敗：\(error.localizedDescription)")) }
                else if let result, result.isFinal { finished = true; continuation.resume(returning: result.bestTranscription.formattedString) }
            }
        }
    }

    func cancel() {
        sessionID = UUID(); stop(); recognition?.cancel(); recognition = nil; request = nil; sink = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
}

/// The audio tap runs on a render thread. Keep its mutable file state behind a lock.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private let request: SFSpeechAudioBufferRecognitionRequest?
    private var file: AVAudioFile?
    private var failed = false
    init(request: SFSpeechAudioBufferRecognitionRequest?, file: AVAudioFile?) { self.request = request; self.file = file }
    var writeFailed: Bool { lock.lock(); defer { lock.unlock() }; return failed }
    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
        lock.lock(); defer { lock.unlock() }
        do { try file?.write(from: buffer) } catch { failed = true }
    }
    func close() { lock.lock(); file = nil; lock.unlock() }
}
