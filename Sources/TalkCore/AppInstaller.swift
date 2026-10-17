import Foundation

/// Installs a downloaded release over the running app: takes the app out of the DMG, checks it is
/// notarized and signed by the same team, then swaps it in once the running copy has quit.
public enum AppInstaller {
    /// Copies the app inside `dmg` to `staging` and detaches the image, whatever happens.
    public static func extractApp(from dmg: URL, into staging: URL) async throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("hyday-update-" + UUID().uuidString)
        let attach = try await run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        guard attach.status == 0 else { throw TalkError("無法打開更新檔，請重新下載。") }
        defer {
            let detach = Process(); detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mount.path, "-force", "-quiet"]
            try? detach.run(); detach.waitUntilExit()
            try? FileManager.default.removeItem(at: mount)
        }
        guard let name = try FileManager.default.contentsOfDirectory(atPath: mount.path).first(where: { $0.hasSuffix(".app") }) else {
            throw TalkError("更新檔裡找不到 Hyday Talk。")
        }
        // Keep a folder made by makeStagingDirectory as is, so its owner-only permissions stay.
        if !FileManager.default.fileExists(atPath: staging.path) {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let destination = staging.appendingPathComponent(name)
        let copy = try await run("/usr/bin/ditto", [mount.appendingPathComponent(name).path, destination.path])
        guard copy.status == 0 else { throw TalkError("無法複製新版，請確認磁碟空間。") }
        return destination
    }

    /// The signing team of an app, read from `codesign -dv`; nil when unsigned or ad-hoc.
    public static func team(of app: URL) async -> String? {
        guard let result = try? await run("/usr/bin/codesign", ["-dv", app.path]), result.status == 0 else { return nil }
        return team(fromCodesignOutput: result.output)
    }

    static func team(fromCodesignOutput output: String) -> String? {
        let line = output.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }
        guard let value = line?.dropFirst("TeamIdentifier=".count), !value.isEmpty, value != "not set" else { return nil }
        return String(value)
    }

    /// Rejects anything that is not a newer copy of `current`, intact, notarized and signed by `team`.
    public static func verify(candidate: URL, current: URL, team expected: String) async throws {
        let failure = TalkError("新版的簽名驗證失敗，已停止更新。")
        guard isSameAppAndNewer(candidate, than: current) else { throw TalkError("下載的檔案不是較新的 Hyday Talk，已停止更新。") }
        guard try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path]).status == 0,
              await team(of: candidate) == expected,
              try await run("/usr/sbin/spctl", ["--assess", "--type", "execute", candidate.path]).status == 0 else { throw failure }
    }

    /// Same bundle identifier and a higher version, so another app or a downgrade is never installed.
    public static func isSameAppAndNewer(_ candidate: URL, than current: URL) -> Bool {
        func info(_ app: URL) -> (id: String, version: String)? {
            guard let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                  let id = plist["CFBundleIdentifier"] as? String, let version = plist["CFBundleShortVersionString"] as? String else { return nil }
            return (id, version)
        }
        guard let new = info(candidate), let old = info(current) else { return false }
        return new.id == old.id && AppUpdate.isNewer(new.version, than: old.version)
    }

    /// A fresh folder only this user can read, so nothing else can stage files for the swap.
    public static func makeStagingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hyday-update-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return directory
    }

    /// Replacing needs write access to the folder holding the app and to the app itself.
    public static func canReplace(_ installed: URL) -> Bool {
        let manager = FileManager.default
        return manager.isWritableFile(atPath: installed.deletingLastPathComponent().path) && manager.isWritableFile(atPath: installed.path)
    }

    /// The code requirement the swapped-in copy must meet: a Developer ID signature from `team`.
    /// The team is quoted because an unquoted identifier starting with a digit is a syntax error.
    public static func signingRequirement(team: String) -> String {
        #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
    }

    /// Starts a detached script that waits for `pid` to exit, swaps `staged` into `installed` and opens
    /// the result with `launcher`. The copy that lands in place is checked again against `team`, since
    /// the staged files could change after `verify`; on any failure the old copy is restored.
    /// `team` is nil only in tests, where the fixtures are unsigned.
    public static func replaceAfterExit(pid: Int32, staged: URL, installed: URL, team: String?,
                                        launcher: String = "/usr/bin/open") throws {
        let check = team == nil ? "true" : #"codesign --verify --deep --strict -R="$5" "$3""#
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        backup="$3.previous-$$"
        mv "$3" "$backup" || { "$4" "$3"; exit 1; }
        if ditto "$2" "$3" && \(check); then rm -rf "$backup"; else rm -rf "$3"; mv "$backup" "$3"; fi
        rm -rf "$(dirname "$2")"
        "$4" "$3"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "hyday-update", String(pid), staged.path, installed.path, launcher,
                             team.map(signingRequirement) ?? ""]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(); let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
                process.standardOutput = pipe; process.standardError = pipe
                do { try process.run() } catch { continuation.resume(throwing: error); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
