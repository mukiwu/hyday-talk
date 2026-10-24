import Foundation
import Combine
import TalkCore

@MainActor
final class LocalSpeechModelManager: ObservableObject {
    @Published private(set) var installed: [String: URL] = [:]
    @Published private(set) var busyModelID: String?
    @Published private(set) var status = ""
    @Published private(set) var issue = ""
    /// Download progress from 0 to 1; nil while verifying or when the size is unknown.
    @Published private(set) var progress: Double?
    /// The model being downloaded, shown in the sidebar; checks of installed models at launch stay out of it.
    @Published private(set) var downloading: LocalSpeechModel?
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var prepared = false
    private let directory = LocalStore.releaseDirectory.appendingPathComponent("Models", isDirectory: true)

    static var enginePath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/whisper-cli").path }
    var engineReady: Bool { CLIExecutableDiscovery.isExecutable(Self.enginePath) }
    static var qwenEnginePath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/transcribe-cli").path }
    func engineReady(for modelPath: String) -> Bool {
        CLIExecutableDiscovery.isExecutable(LocalSpeechModel.engine(forModelPath: modelPath) == .qwen ? Self.qwenEnginePath : Self.enginePath)
    }

    func prepare(currentPath: String, onSelect: @escaping (URL) -> Void) {
        guard !prepared else { return }; prepared = true
        let current = URL(fileURLWithPath: (currentPath as NSString).expandingTildeInPath)
        let legacy = LocalSpeechModel.all.first { $0.filename == current.lastPathComponent }
        generation = UUID(); let run = generation
        busyModelID = legacy?.id ?? LocalSpeechModel.recommended.id; status = "正在驗證模型"
        operation = Task {
            defer { if generation == run { busyModelID = nil; status = ""; operation = nil } }
            do {
                for model in LocalSpeechModel.all {
                    let destination = directory.appendingPathComponent(model.filename)
                    let source = FileManager.default.fileExists(atPath: destination.path) ? destination
                        : (legacy?.id == model.id && SpeechCLIConfiguration.isReadableModel(current.path) ? current : nil)
                    guard let source else { continue }
                    do {
                        let installedURL: URL
                        if source.standardizedFileURL == destination.standardizedFileURL {
                            try await LocalModelInstaller.validate(source: source, model: model); installedURL = destination
                        } else {
                            installedURL = try await LocalModelInstaller.install(source: source, model: model, directory: directory)
                        }
                        try Task.checkCancellation(); guard generation == run else { return }
                        installed[model.id] = installedURL
                    } catch is CancellationError { throw CancellationError() }
                    catch { issue = "模型檔案驗證失敗，請重新下載。" }
                }
                try Task.checkCancellation(); guard generation == run else { return }
                if let selected = legacy.flatMap({ installed[$0.id] }) ?? installed[LocalSpeechModel.recommended.id] {
                    onSelect(selected)
                }
            } catch is CancellationError { }
            catch { issue = "無法準備本機模型，請重新下載。" }
        }
    }

    func download(_ model: LocalSpeechModel, onSelect: @escaping (URL) -> Void) {
        guard busyModelID == nil else { return }
        generation = UUID(); let run = generation
        busyModelID = model.id; status = "正在下載模型"; issue = ""; downloading = model
        operation = Task {
            defer { if generation == run { busyModelID = nil; status = ""; progress = nil; downloading = nil; operation = nil } }
            do {
                // The timeout counts idle time between packets, so a stalled connection fails within a minute.
                var request = URLRequest(url: model.downloadURL); request.timeoutInterval = 60
                let tracker = DownloadProgress { [weak self] fraction in
                    Task { @MainActor in if self?.generation == run { self?.progress = fraction } }
                }
                let (temporary, response) = try await Self.fetch(request, delegate: tracker)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation(); guard generation == run else { return }
                guard [200, 206].contains((response as? HTTPURLResponse)?.statusCode ?? 0) else { throw TalkError("模型下載失敗，請確認網路後重試。") }
                status = "正在驗證模型"; progress = nil
                let url = try await LocalModelInstaller.install(source: temporary, model: model, directory: directory)
                try Task.checkCancellation(); guard generation == run else { return }
                installed[model.id] = url; onSelect(url)
            } catch is CancellationError { }
            catch { if generation == run { issue = "模型下載或驗證失敗，請確認網路與磁碟空間後重試。" } }
        }
    }

    /// Removes an installed model file. The caller keeps the selected model out of reach.
    func delete(_ model: LocalSpeechModel) {
        guard busyModelID == nil, let url = installed[model.id] else { return }
        do {
            try FileManager.default.removeItem(at: url)
            installed[model.id] = nil; issue = ""
        } catch { issue = "無法刪除模型檔案，請確認檔案權限後重試。" }
    }

    /// Downloads with up to three resumes, continuing from the bytes already received when the connection drops.
    private static func fetch(_ request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> (URL, URLResponse) {
        var resumeData: Data?
        for attempt in 1...4 {
            do {
                if let data = resumeData { return try await URLSession.shared.download(resumeFrom: data, delegate: delegate) }
                return try await URLSession.shared.download(for: request, delegate: delegate)
            } catch let error as URLError where attempt < 4 && error.code != .cancelled {
                resumeData = error.downloadTaskResumeData ?? resumeData
            }
        }
        throw URLError(.networkConnectionLost)
    }

    func cancel() {
        generation = UUID(); operation?.cancel(); operation = nil; busyModelID = nil; status = ""; progress = nil; downloading = nil
    }
}

/// Reports a download's fraction completed from the task URLSession creates for it.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        var last = -1
        // Fires for every received chunk; only whole percentages reach the UI.
        observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
            let percent = Int(progress.fractionCompleted * 100)
            guard percent != last else { return }
            last = percent; report(Double(percent) / 100)
        }
    }
}
