import AppKit
import Combine
import TalkCore

/// Downloads the recommended Ollama text model. Lives on AppModel so the
/// download and its progress survive leaving the settings page.
@MainActor
final class TextModelInstaller: ObservableObject {
    @Published private(set) var installing = false
    @Published private(set) var progress: Double?
    @Published private(set) var issue = ""
    let model = LocalTextClient.recommendedModel

    var status: String { progress.map { "正在下載 \(Int($0 * 100))%" } ?? "正在準備下載" }

    func install(onDone: @escaping @MainActor () async -> Void) {
        guard !installing else { return }
        installing = true; issue = ""; progress = nil
        Task {
            defer { installing = false }
            do {
                try await LocalTextClient.pull(model) { value in
                    Task { @MainActor [weak self] in if let value { self?.progress = value } }
                }
                await onDone()
            } catch is CancellationError { }
            catch { issue = error.localizedDescription }
        }
    }
}

/// Checks GitHub for a newer release and downloads its DMG. When asked, it swaps the new
/// version in and relaunches; where the app cannot be replaced, the DMG is opened instead.
@MainActor
final class AppUpdater: ObservableObject {
    enum State: Equatable { case idle, available, downloading(Double), ready(URL), installing, failed(String) }
    @Published private(set) var update: AppUpdate?
    @Published private(set) var state: State = .idle
    private var lastCheck: Date?
    private var download: Task<Void, Never>?
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Checks at most every six hours; failures stay silent, since this is only a hint.
    func checkIfDue() {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 6 * 3600 { return }
        guard download == nil else { return }
        lastCheck = Date()
        Task {
            var request = URLRequest(url: AppUpdate.latestReleaseURL); request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let found = AppUpdate.parse(data, current: Self.currentVersion) else { return }
            if found != update { update = found; state = .available }
        }
    }

    func startDownload() {
        guard let update, download == nil else { return }
        state = .downloading(0)
        download = Task {
            defer { download = nil }
            do {
                let file = try await DMGDownload.run(update.dmg) { fraction in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.state { self?.state = .downloading(fraction) }
                    }
                }
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                let destination = downloads.appendingPathComponent("Hyday-Talk-\(update.version).dmg")
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: file, to: destination)
                state = .ready(destination)
            } catch is CancellationError { state = .available }
            catch { state = .failed("更新下載失敗，請重試。") }
        }
    }

    func cancelDownload() { download?.cancel() }

    /// Opens the DMG so the user can drag the new version into Applications.
    func openInstaller() {
        guard case .ready(let file) = state else { return }
        NSWorkspace.shared.open(file)
    }

    /// False when the app sits somewhere this user cannot write, so the DMG has to be opened instead.
    var canRestartToUpdate: Bool { AppInstaller.canReplace(Bundle.main.bundleURL) }

    /// Checks the downloaded version, quits, and lets a helper swap it in and relaunch.
    func restartToUpdate() {
        guard case .ready(let file) = state else { return }
        state = .installing
        Task {
            do {
                let current = Bundle.main.bundleURL
                guard let team = await AppInstaller.team(of: current) else { throw TalkError("目前的版本沒有簽名，請改用安裝檔更新。") }
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Hyday Talk Update", isDirectory: true)
                let staged = try await AppInstaller.extractApp(from: file, into: staging)
                try await AppInstaller.verify(candidate: staged, team: team)
                try AppInstaller.replaceAfterExit(pid: ProcessInfo.processInfo.processIdentifier, staged: staged, installed: current)
                NSApp.terminate(nil)
            } catch {
                state = .failed((error as? TalkError)?.message ?? "無法自動更新，請改用安裝檔。")
            }
        }
    }
}

private final class DMGDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    static func run(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DMGDownload(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation; task.resume()
            }
        } onCancel: { task.cancel() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns, so keep a copy first.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            guard status == 200 else { throw TalkError("更新下載失敗，請重試。") }
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch { continuation?.resume(throwing: error) }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        continuation = nil
    }
}
