import XCTest
@testable import TalkCore

final class ClaudeSessionTests: XCTestCase {
    private var directory: URL!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    /// A stand-in for `claude -p` in stream-json mode: logs each launch with its arguments,
    /// then answers every user message with the launch count and the message text.
    private func fakeClaude(failing: Bool = false) -> String {
        let path = directory.appendingPathComponent("claude").path
        let script = """
        #!/usr/bin/python3
        import json, sys
        log = '\(directory.appendingPathComponent("launches").path)'
        with open(log, 'a') as f: f.write(' '.join(sys.argv[1:]) + '\\n')
        n = len(open(log).read().splitlines())
        for line in sys.stdin:
            text = json.loads(line)['message']['content']
            print(json.dumps({'type': 'system', 'subtype': 'init'}), flush=True)
            print(json.dumps({'type': 'result', 'is_error': \(failing ? "True" : "False"), 'result': f'{n}:{text}'}), flush=True)
        """
        FileManager.default.createFile(atPath: path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
        return path
    }
    private var launches: [String] {
        ((try? String(contentsOf: directory.appendingPathComponent("launches"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    func testReusesOneProcessAcrossMessages() async throws {
        let session = ClaudeSession(executable: fakeClaude(), workingDirectory: directory)
        let first = try await session.complete(prompt: "第一句", model: "claude-haiku-5-5")
        let second = try await session.complete(prompt: "第二句", model: "claude-haiku-5-5")
        await session.stop()
        XCTAssertEqual(first, "1:第一句")
        XCTAssertEqual(second, "1:第二句")
        XCTAssertEqual(launches.count, 1)
        XCTAssertTrue(launches[0].contains("--model claude-haiku-5-5"))
        XCTAssertTrue(launches[0].contains("--input-format stream-json"))
    }

    func testRestartsWhenModelChanges() async throws {
        let session = ClaudeSession(executable: fakeClaude(), workingDirectory: directory)
        _ = try await session.complete(prompt: "a", model: "claude-haiku-5-5")
        let answer = try await session.complete(prompt: "b", model: "claude-sonnet-5-5")
        await session.stop()
        XCTAssertEqual(answer, "2:b")
        XCTAssertTrue(launches[1].contains("--model claude-sonnet-5-5"))
    }

    func testRestartsAfterTurnLimitSoHistoryDoesNotPileUp() async throws {
        let session = ClaudeSession(executable: fakeClaude(), workingDirectory: directory, turnLimit: 2)
        var answers: [String] = []
        for text in ["a", "b", "c"] { answers.append(try await session.complete(prompt: text, model: "m")) }
        await session.stop()
        XCTAssertEqual(answers, ["1:a", "1:b", "2:c"])
    }

    func testErrorResultIsReportedAndNextMessageStartsFresh() async throws {
        let session = ClaudeSession(executable: fakeClaude(failing: true),
                                    workingDirectory: directory)
        do { _ = try await session.complete(prompt: "a", model: "m"); XCTFail("expected error") }
        catch let error as TalkError { XCTAssertTrue(error.message.contains("Claude")) }
        await session.stop()
    }

    func testProcessThatExitsIsRestartedOnNextMessage() async throws {
        let path = directory.appendingPathComponent("claude").path
        let script = "#!/bin/bash\necho x >> '\(directory.appendingPathComponent("launches").path)'\nexit 1\n"
        FileManager.default.createFile(atPath: path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
        let session = ClaudeSession(executable: path, workingDirectory: directory)
        for _ in 0..<2 {
            do { _ = try await session.complete(prompt: "a", model: "m"); XCTFail("expected error") } catch {}
        }
        XCTAssertEqual(launches.count, 2)
    }
}

final class ClaudeTextSettingsTests: XCTestCase {
    func testDefaultsToHaikuAndKeepsTheChosenModel() throws {
        var settings = TalkSettings()
        XCTAssertEqual(settings.claudeModel, .haiku)
        settings.claudeModel = .sonnet
        let decoded = try JSONDecoder().decode(TalkSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.claudeModel, .sonnet)
        XCTAssertTrue(TextBackend.availableSources.contains(.claude))
    }
}
