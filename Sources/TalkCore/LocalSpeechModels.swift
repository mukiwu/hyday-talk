import Foundation
import CryptoKit

/// whisper.cpp runs GGML `.bin` Whisper models; transcribe.cpp runs GGUF Qwen3-ASR models.
public enum SpeechEngine: Sendable { case whisper, qwen }

public struct LocalSpeechModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let filename: String
    public let bytes: Int64
    public let sha256: String
    public let repository: String
    public var engine: SpeechEngine { Self.engine(forModelPath: filename) }
    public static func engine(forModelPath path: String) -> SpeechEngine {
        path.lowercased().hasSuffix(".gguf") ? .qwen : .whisper
    }
    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(filename)")!
    }
    public var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    public static let whisperTurbo = LocalSpeechModel(id: "large-v3-turbo-q5_0", title: "Whisper Large v3 Turbo",
        detail: "支援中文與多語辨識。", filename: "ggml-large-v3-turbo-q5_0.bin", bytes: 574_041_195,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2")
    public static let qwenSmall = LocalSpeechModel(id: "qwen3-asr-0.6b-q8_0", title: "Qwen3-ASR 0.6B",
        detail: "中文口語與中英夾雜辨識較準，速度快。", filename: "Qwen3-ASR-0.6B-Q8_0.gguf", bytes: 850_423_456,
        sha256: "f081b2d5e23bd669d92cc331d722a8a0681943b8e6f34b48996fd5c319b5acd8",
        repository: "handy-computer/Qwen3-ASR-0.6B-gguf")
    public static let qwenLarge = LocalSpeechModel(id: "qwen3-asr-1.7b-q6_k", title: "Qwen3-ASR 1.7B",
        detail: "辨識最準確，需要較多儲存空間與記憶體。", filename: "Qwen3-ASR-1.7B-Q6_K.gguf", bytes: 1_692_554_208,
        sha256: "c75a961b7134a6c952d89797865cb0d0376876185aee04ef6d12c31c2952e4e1",
        repository: "handy-computer/Qwen3-ASR-1.7B-gguf")
    /// Qwen3-ASR 1.7B fine-tuned for Taiwan Mandarin; converted from JacobLinCool/TEA-ASR-1.1 (MIT)
    /// with transcribe.cpp's Qwen3-ASR converter and quantized to Q6_K.
    public static let tea = LocalSpeechModel(id: "tea-asr-1.1-q6_k", title: "TEA-ASR 1.1",
        detail: "針對台灣口語調校，直接輸出繁體與台灣用詞，中英夾雜也準。", filename: "TEA-ASR-1.1-Q6_K.gguf", bytes: 1_692_286_464,
        sha256: "2417fa52d49f852bfc11704190e10ddb681c343a661a3a3d1bb213876c780b68",
        repository: "mukiwu/TEA-ASR-1.1-transcribe-gguf")
    /// Selected first when installed.
    public static let recommended = qwenSmall
    /// Marked as recommended in the model list.
    public var isRecommended: Bool { self == .qwenSmall || self == .tea }
    public static let all: [LocalSpeechModel] = [whisperTurbo, qwenSmall, qwenLarge, tea]

    public init(id: String, title: String, detail: String, filename: String, bytes: Int64, sha256: String,
                repository: String = "ggerganov/whisper.cpp") {
        self.id = id; self.title = title; self.detail = detail; self.filename = filename
        self.bytes = bytes; self.sha256 = sha256; self.repository = repository
    }
}

public enum LocalModelInstaller {
    public static func validate(source: URL, model: LocalSpeechModel) async throws {
        let worker = Task.detached(priority: .utility) { try verify(source: source, model: model, output: nil) }
        try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    /// Stream the model into a private staging file, verifying it before an
    /// atomic replacement. Cancellation or corrupt downloads preserve the old model.
    public static func install(source: URL, model: LocalSpeechModel, directory: URL) async throws -> URL {
        let worker = Task.detached(priority: .utility) { try installFile(source: source, model: model, directory: directory) }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    private static func installFile(source: URL, model: LocalSpeechModel, directory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(model.filename)
        let staging = directory.appendingPathComponent(".download-" + UUID().uuidString)
        guard manager.createFile(atPath: staging.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw TalkError("無法儲存模型，請確認磁碟空間後重試。")
        }
        defer { try? manager.removeItem(at: staging) }
        let output = try FileHandle(forWritingTo: staging)
        defer { try? output.close() }
        try verify(source: source, model: model, output: output)
        try output.synchronize(); try Task.checkCancellation()
        guard rename(staging.path, destination.path) == 0 else { throw TalkError("無法儲存模型，請確認磁碟空間後重試。") }
        return destination
    }

    private static func verify(source: URL, model: LocalSpeechModel, output: FileHandle?) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hash = SHA256(); var count: Int64 = 0
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            count += Int64(data.count)
            guard count <= model.bytes else { throw TalkError("模型檔案驗證失敗，請重新下載。") }
            hash.update(data: data); try output?.write(contentsOf: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == model.bytes, digest == model.sha256 else { throw TalkError("模型檔案驗證失敗，請重新下載。") }
        try Task.checkCancellation()
    }
}

public enum LocalSpeechConfiguration {
    /// Keep legacy settings decodable; CLI fields remain stored for rollback.
    public static func migrate(_ settings: inout TalkSettings, engine: String) {
        if settings.speechBackend == .cli {
            if SpeechCLIConfiguration.isWhisper(settings.speechCLIExecutable),
               let model = SpeechCLIConfiguration.whisperModelPath(arguments: settings.speechCLIArguments),
               SpeechCLIConfiguration.isReadableModel(model) { settings.whisperModel = model }
            settings.speechBackend = .whisper
        }
        if CLIExecutableDiscovery.isExecutable(engine) { settings.whisperExecutable = engine }
    }
}
