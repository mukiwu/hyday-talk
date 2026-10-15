import XCTest
import CryptoKit
@testable import TalkCore

final class LocalSpeechModelTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Hyday Model Test " + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func descriptor(for data: Data) -> LocalSpeechModel {
        LocalSpeechModel(id: "test", title: "Test", detail: "Test", filename: "fixture.bin", bytes: Int64(data.count),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    func testVerifiedModelIsInstalledWithoutChangingSource() async throws {
        let data = Data("verified model fixture".utf8)
        let source = root.appendingPathComponent("source.bin"); try data.write(to: source)
        let result = try await LocalModelInstaller.install(source: source, model: descriptor(for: data), directory: root.appendingPathComponent("Models"))
        XCTAssertEqual(try Data(contentsOf: result), data)
        XCTAssertEqual(try Data(contentsOf: source), data)
        try await LocalModelInstaller.validate(source: result, model: descriptor(for: data))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: result.deletingLastPathComponent().path).contains { $0.hasPrefix(".download-") })
    }

    func testCancelledInstallationPreservesExistingModel() async throws {
        let data = Data(repeating: 1, count: 2_097_152); let model = descriptor(for: data)
        let source = root.appendingPathComponent("source.bin"); try data.write(to: source)
        let directory = root.appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appendingPathComponent(model.filename)
        let original = Data("original".utf8); try original.write(to: existing)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LocalModelInstaller.install(source: source, model: model, directory: directory)
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled installation must not promote the model") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: existing), original)
    }

    func testCorruptDownloadDoesNotReplaceExistingModel() async throws {
        let data = Data("trusted".utf8); let model = descriptor(for: data)
        let directory = root.appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appendingPathComponent(model.filename); try data.write(to: existing)
        let source = root.appendingPathComponent("bad.bin")
        for invalid in [Data("wrong!!".utf8), Data("short".utf8), Data("oversized invalid data".utf8)] {
            try invalid.write(to: source)
            do { _ = try await LocalModelInstaller.install(source: source, model: model, directory: directory); XCTFail("Corrupt weights must be rejected") }
            catch { XCTAssertTrue(error.localizedDescription.contains("驗證失敗")) }
            XCTAssertEqual(try Data(contentsOf: existing), data)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [model.filename])
        }
    }

    func testWhisperCLIMigrationPreservesModelLanguageAndTextSettings() throws {
        let model = root.appendingPathComponent("舊模型 file.bin"); try Data("model".utf8).write(to: model)
        let engine = root.appendingPathComponent("whisper-cli")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: engine)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)
        var settings = TalkSettings(); settings.speechBackend = .cli
        settings.speechCLIExecutable = "/opt/homebrew/bin/whisper-cli"
        settings.speechCLIArguments = SpeechCLIConfiguration.whisperArguments(modelPath: model.path)
        settings.locale = "ja-JP"; settings.textBackend = .api; settings.autoInsert = false
        let arguments = settings.speechCLIArguments
        LocalSpeechConfiguration.migrate(&settings, engine: engine.path)
        XCTAssertEqual(settings.speechBackend, .whisper)
        XCTAssertEqual(settings.whisperModel, model.path)
        XCTAssertEqual(settings.whisperExecutable, engine.path)
        XCTAssertEqual(settings.locale, "ja-JP"); XCTAssertEqual(settings.textBackend, .api)
        XCTAssertFalse(settings.autoInsert); XCTAssertEqual(settings.speechCLIArguments, arguments)
    }

    func testSystemAndAPISourceRemainSelectedDuringMigration() {
        for backend in [SpeechBackend.system, .api] {
            var settings = TalkSettings(); settings.speechBackend = backend
            LocalSpeechConfiguration.migrate(&settings, engine: "/missing")
            XCTAssertEqual(settings.speechBackend, backend)
        }
    }

    func testModelsListWhisperAndQwenWithTheirOwnSources() {
        XCTAssertEqual(LocalSpeechModel.all.map(\.id), ["large-v3-turbo-q5_0", "qwen3-asr-0.6b-q8_0", "qwen3-asr-1.7b-q6_k", "tea-asr-1.1-q6_k"])
        XCTAssertEqual(LocalSpeechModel.recommended, LocalSpeechModel.qwenSmall)
        XCTAssertEqual(LocalSpeechModel.whisperTurbo.downloadURL.absoluteString,
                       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")
        XCTAssertEqual(LocalSpeechModel.whisperTurbo.engine, .whisper)
        let qwen = LocalSpeechModel.qwenSmall
        XCTAssertEqual(qwen.engine, .qwen)
        XCTAssertEqual(qwen.downloadURL.absoluteString,
                       "https://huggingface.co/handy-computer/Qwen3-ASR-0.6B-gguf/resolve/main/Qwen3-ASR-0.6B-Q8_0.gguf")
        XCTAssertEqual(qwen.bytes, 850_423_456)
        XCTAssertEqual(LocalSpeechModel.engine(forModelPath: "/m/Qwen3-ASR-0.6B-Q8_0.gguf"), .qwen)
        XCTAssertEqual(LocalSpeechModel.engine(forModelPath: "/m/ggml-small.bin"), .whisper)
        XCTAssertEqual(LocalSpeechModel.tea.engine, .qwen)
        XCTAssertEqual(LocalSpeechModel.all.filter(\.isRecommended), [LocalSpeechModel.qwenSmall, LocalSpeechModel.tea])
        XCTAssertEqual(LocalSpeechModel.tea.downloadURL.absoluteString,
                       "https://huggingface.co/mukiwu/TEA-ASR-1.1-transcribe-gguf/resolve/main/TEA-ASR-1.1-Q6_K.gguf")
    }
}
