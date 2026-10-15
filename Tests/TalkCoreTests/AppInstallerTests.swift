import XCTest
@testable import TalkCore

final class AppInstallerTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Hyday Installer " + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func fakeApp(named name: String = "Hyday Talk.app", marker: String) throws -> URL {
        let app = root.appendingPathComponent("build-\(marker)").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: app.appendingPathComponent("Contents/marker"))
        return app
    }
    private func marker(_ app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker"), encoding: .utf8)
    }

    func testExtractsTheAppFromADiskImageAndDetachesIt() async throws {
        let app = try fakeApp(marker: "new")
        let folder = app.deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Applications"),
                                                   withDestinationURL: URL(fileURLWithPath: "/Applications"))
        let dmg = root.appendingPathComponent("update.dmg")
        _ = try await ProcessRunner.run(executable: "/usr/bin/hdiutil",
            arguments: ["create", "-volname", "Hyday Talk", "-srcfolder", folder.path, "-format", "UDZO", dmg.path], timeout: 60)

        let extracted = try await AppInstaller.extractApp(from: dmg, into: root.appendingPathComponent("staging"))
        XCTAssertEqual(extracted.lastPathComponent, "Hyday Talk.app")
        XCTAssertEqual(marker(extracted), "new")
        let mounts = try await ProcessRunner.run(executable: "/usr/bin/hdiutil", arguments: ["info"], timeout: 20)
        XCTAssertFalse(mounts.contains(dmg.path))
    }

    func testReadsTheTeamFromCodesignOutput() {
        let output = "Executable=/A.app/Contents/MacOS/A\nIdentifier=io.hyday.talk\nTeamIdentifier=ABCDE12345\nSealed Resources version=2"
        XCTAssertEqual(AppInstaller.team(fromCodesignOutput: output), "ABCDE12345")
        XCTAssertNil(AppInstaller.team(fromCodesignOutput: "TeamIdentifier=not set"))
    }

    func testUnsignedCandidateIsRejected() async throws {
        let app = try fakeApp(marker: "unsigned")
        do { try await AppInstaller.verify(candidate: app, team: "ABCDE12345"); XCTFail("unsigned app must be rejected") }
        catch let error as TalkError { XCTAssertTrue(error.message.contains("簽名")) }
    }

    func testReplacementWaitsForTheAppToQuitThenSwapsAndRelaunches() async throws {
        let installed = try fakeApp(marker: "old")
        let staged = try fakeApp(marker: "new")
        let launched = root.appendingPathComponent("launched")
        let launcher = root.appendingPathComponent("launcher")
        try Data("#!/bin/sh\necho \"$1\" > '\(launched.path)'\n".utf8).write(to: launcher)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        let running = Process(); running.executableURL = URL(fileURLWithPath: "/bin/sleep"); running.arguments = ["1"]
        try running.run()

        try AppInstaller.replaceAfterExit(pid: running.processIdentifier, staged: staged, installed: installed, launcher: launcher.path)
        XCTAssertEqual(marker(installed), "old", "nothing is replaced while the app is still running")
        running.waitUntilExit()
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: launched.path), Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }

        XCTAssertEqual(marker(installed), "new")
        XCTAssertEqual(try String(contentsOf: launched, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), installed.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["Hyday Talk.app"], "the old copy is removed after a successful swap")
    }

    func testOnlyWritableInstallLocationsAreReplaceable() throws {
        let installed = try fakeApp(marker: "old")
        XCTAssertTrue(AppInstaller.canReplace(installed))
        XCTAssertFalse(AppInstaller.canReplace(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
    }
}
