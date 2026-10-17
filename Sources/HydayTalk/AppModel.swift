import AppKit
import AVFoundation
import Speech
import Combine
import TalkCore

enum CapturePhase: Equatable {
    case idle, preparing, recording, transcribing, processing, done, failed
    var busy: Bool { [.preparing, .recording, .transcribing, .processing].contains(self) }
    var title: String {
        switch self {
        case .idle: return "等待語音輸入"
        case .preparing: return "正在準備麥克風"
        case .recording: return "正在錄音"
        case .transcribing: return "正在辨識語音"
        case .processing: return "正在整理文字"
        case .done: return "文字處理完成"
        case .failed: return "處理失敗"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var settings = TalkSettings() {
        didSet {
            guard loaded else { return }
            saveWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.saveSettings() }
            saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
    @Published private(set) var history: [DictationRecord] = []
    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var action: VoiceAction = .dictate
    @Published private(set) var transcript = ""
    @Published private(set) var result = ""
    @Published var notice = ""
    /// Set when the output had nowhere to go, so the panel stays up with a copy button.
    @Published private(set) var missedInsertion = false
    @Published var showPermissionGuide = false
    @Published private(set) var requestingPermission: PermissionKind?
    private(set) var permissionGuideStartStep: PermissionKind?
    @Published private(set) var level = 0.0
    @Published private(set) var elapsed = 0.0
    @Published private(set) var microphoneAllowed = false
    @Published private(set) var speechAllowed = false
    @Published private(set) var accessibilityAllowed = false
    @Published private(set) var shortcutReady = false
    @Published private(set) var destination = ""
    var showWindow: (() -> Void)?
    var onPanelChange: (() -> Void)?
    private let store = LocalStore()
    private var pruneTimer: Timer?
    let localModels = LocalSpeechModelManager()
    let textModelInstaller = TextModelInstaller()
    private var claudeSession: ClaudeSession?
    let updater = AppUpdater()
    private let audio = AudioCapture()
    private let shortcuts = GlobalShortcuts()
    private var loaded = false
    private var saveWork: DispatchWorkItem?
    private var permissionsTimer: Timer?
    private var recordingTimer: Timer?
    private var operation: Task<Void, Never>?
    private var started = Date()
    private var sessionID = UUID()
    private var target: InputTarget?
    private var pendingCorrection: PendingCorrection?
    private var correctionTimer: Timer?
    private var correctionTask: Task<Void, Never>?
    private var sessionSettings = TalkSettings()
    private var sessionHints: [String] = []
    private var sessionContext: ScreenContext?
    /// Entities and tags from the Hyday folder; only ever used as recognition hints.
    @Published private(set) var lastCorrectionCheck: CorrectionCheck?
    @Published private(set) var hydayVocabulary: [String] = []
    @Published private(set) var scanningHydayVocabulary = false
    private var vocabularyTask: Task<Void, Never>?
    @Published private(set) var usage = UsageLedger()
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        do {
            settings = try store.load(TalkSettings.self, from: "settings.json") ?? TalkSettings()
            settings.dictationLayout = nil // 段落與列表改由自動整理混合排版
        } catch { notice = "無法讀取本機設定，原檔案已備份。請檢查 Application Support/HydayTalk。" }
        do {
            history = try store.load([DictationRecord].self, from: "history.json") ?? []
        } catch { notice += " 無法讀取本機紀錄，原檔案已保留或備份。" }
        if var saved = try? store.load(UsageLedger.self, from: "usage.json") {
            saved.backfillBreakdown(from: history); usage = saved; saveUsage()
        }
        else { usage = UsageLedger(seedingFrom: history); saveUsage() }
        let originalSettings = settings
        LocalSpeechConfiguration.migrate(&settings, engine: LocalSpeechModelManager.enginePath)
        LocalTextConfiguration.migrate(&settings)
        loaded = true
        if settings != originalSettings { saveSettings() }
        audio.onTranscript = { [weak self] text in self?.transcript = text }
        audio.onLevel = { [weak self] level in self?.level = level; MeterDiagnostics.shared.record(level: level) }
        audio.onFailure = { [weak self] error in
            guard let self, self.phase == .recording else { return }
            self.notice = error.localizedDescription; self.finish()
        }
        shortcuts.isBusy = { [weak self] in self?.phase.busy == true }
        shortcuts.onAvailability = { [weak self] in self?.shortcutReady = $0 }
        shortcuts.onReturnKey = { [weak self] in self?.checkCorrectionsBeforeReturn() }
        shortcuts.onAction = { [weak self] shortcut in
            guard let self else { return }
            switch shortcut {
            case .cancel: self.cancel()
            case .voice(let action):
                if self.phase == .recording { self.finish() }
                else if !self.phase.busy { self.begin(action: action) }
            }
        }
    }

    func start() {
        AudioCapture.cleanAbandonedAudio()
        localModels.prepare(currentPath: settings.whisperModel) { [weak self] url in
            self?.settings.whisperModel = url.path
        }
        TextInsertion.startTracking()
        pruneRecordings()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneRecordings() }
        }
        refreshPermissions()
        reloadHydayVocabulary()
        permissionsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancel(); TextInsertion.forgetDestination() }
            })
        }
    }

    func shutdown() {
        localModels.cancel()
        stopWatchingCorrections(); correctionTask?.cancel()
        cancel(); shortcuts.stop(); permissionsTimer?.invalidate(); saveWork?.cancel(); saveSettings()
        TextInsertion.stopTracking()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func refreshPermissions() {
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechAllowed = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityAllowed = AXIsProcessTrusted()
        if accessibilityAllowed { shortcuts.start() } else if shortcutReady { shortcuts.stop() }
    }

    var requiredPermissions: [PermissionKind] {
        settings.speechBackend == .system ? [.microphone, .speech, .accessibility] : [.microphone, .accessibility]
    }
    var completedPermissionCount: Int { requiredPermissions.filter(permissionAllowed).count }
    var permissionsReady: Bool { completedPermissionCount == requiredPermissions.count && shortcutReady }
    func permissionAllowed(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .microphone: return microphoneAllowed
        case .speech: return speechAllowed
        case .accessibility: return accessibilityAllowed
        }
    }
    func authorization(for kind: PermissionKind) -> PermissionAuthorization {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .restricted
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .restricted
            }
        case .accessibility: return accessibilityAllowed ? .granted : .denied
        }
    }
    func openPermissionGuide(at step: PermissionKind? = nil) {
        guard !phase.busy else { return }
        refreshPermissions(); permissionGuideStartStep = step
        UserDefaults.standard.set(true, forKey: "permissionGuideSeen")
        showPermissionGuide = true
    }
    func presentPermissionGuideIfNeeded() {
        refreshPermissions()
        if !permissionsReady && !UserDefaults.standard.bool(forKey: "permissionGuideSeen") { openPermissionGuide() }
    }

    func grantMicrophone() {
        guard requestingPermission == nil else { return }
        requestingPermission = .microphone
        Task {
            defer { requestingPermission = nil }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { _ = await AudioCapture.requestMicrophone() }
            else if !microphoneAllowed { openPrivacy("Microphone") }
            refreshPermissions()
        }
    }
    func grantSpeech() {
        guard requestingPermission == nil else { return }
        requestingPermission = .speech
        Task {
            defer { requestingPermission = nil }
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined { _ = await AudioCapture.requestSpeech() }
            else if !speechAllowed { openPrivacy("SpeechRecognition") }
            refreshPermissions()
        }
    }
    func grantAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
    }
    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) { NSWorkspace.shared.open(url) }
    }

    /// The folder chosen on the Hyday page, otherwise Hyday's own configured folder.
    var hydayRoot: URL? {
        if let folder = settings.hydayFolder {
            let url = URL(fileURLWithPath: folder)
            return HydayVault.isDirectory(url) ? url : nil
        }
        return HydayVault.configuredRoot()
    }

    func reloadHydayVocabulary() {
        vocabularyTask?.cancel()
        guard let root = hydayRoot else { hydayVocabulary = []; return }
        scanningHydayVocabulary = true
        vocabularyTask = Task {
            let terms = try? await Task.detached(priority: .utility) { try HydayVocabulary.scan(root: root) }.value
            guard !Task.isCancelled else { return }
            hydayVocabulary = terms ?? []; scanningHydayVocabulary = false
        }
    }

    func begin(action: VoiceAction = .dictate) {
        guard !phase.busy else { return }
        if action == .hyday, hydayRoot == nil {
            self.action = action; result = ""
            fail(TalkError("請先在 Hyday 頁設定 Hyday 資料夾。")); return
        }
        refreshPermissions()
        if !microphoneAllowed || (settings.speechBackend == .system && !speechAllowed) {
            openPermissionGuide(at: !microphoneAllowed ? .microphone : .speech)
            showWindow?()
            return
        }
        checkCorrections()
        result = ""
        let snapshot = settings
        do { try validate(snapshot, action: action) }
        catch { fail(error); return }
        // Start Claude Code while the user is still speaking, so formatting skips the CLI start-up.
        if snapshot.textBackend == .claude, snapshot.requiresTextModel(for: action), let session = claude() {
            Task { await session.prepare(model: snapshot.claudeModel.rawValue) }
        }
        let focused = TextInsertion.capture()
        target = action == .hyday ? nil : focused
        if target?.secure == true { fail(TalkError("這是密碼欄位。請改在一般文字輸入框使用。")); return }
        // Read before the panel appears, while the cursor is still where the user will type.
        sessionContext = focused.flatMap { snapshot.shouldReadScreenContext(for: action, app: $0.name) ? TextInsertion.screenContext(of: $0) : nil }
        sessionID = UUID(); let current = sessionID
        sessionSettings = snapshot; self.action = action
        sessionHints = RecognitionHints.terms(dictionary: snapshot.dictionary, vocabulary: hydayVocabulary)
        let hints = sessionHints
        result = ""; transcript = ""; notice = ""; missedInsertion = false; elapsed = 0; level = 0; failedRecordID = nil
        destination = action == .hyday ? "Hyday"
            : (snapshot.autoInsert && action != .ask && (target?.editable != true || target?.element == nil)
               ? "剪貼簿" : (target?.name ?? "結果區"))
        phase = .preparing; onPanelChange?()
        operation = Task {
            do {
                var microphone = microphoneAllowed
                if !microphone && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    microphone = await AudioCapture.requestMicrophone()
                }
                guard microphone else { throw TalkError("請允許麥克風存取，再開始錄音。") }
                if snapshot.speechBackend == .system {
                    var speech = speechAllowed
                    if !speech && SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                        speech = await AudioCapture.requestSpeech()
                    }
                    guard speech else { throw TalkError("請允許語音辨識，或改用本機模型、API。") }
                }
                try Task.checkCancellation()
                guard sessionID == current else { return }
                refreshPermissions(); try audio.start(settings: snapshot, hints: hints)
                started = Date(); phase = .recording
                if snapshot.interactionSounds { NSSound(named: "Tink")?.play() }
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.phase == .recording else { return }
                        self.elapsed = Date().timeIntervalSince(self.started)
                        let limit = snapshot.speechBackend == .system ? 55.0 : 180.0
                        if self.elapsed >= limit {
                            self.notice = "已達單次錄音上限（\(Int(limit)) 秒），正在完成辨識。"; self.finish()
                        }
                    }
                }
                onPanelChange?()
            } catch is CancellationError { }
            catch { if sessionID == current { fail(error) } }
        }
    }

    func finish() {
        guard phase == .recording else { return }
        recordingTimer?.invalidate(); recordingTimer = nil
        let spokeAt = Date()
        elapsed = spokeAt.timeIntervalSince(started); audio.stop(); level = 0
        MeterDiagnostics.shared.report(elapsed: elapsed)
        let duration = elapsed; let current = sessionID; let snapshot = sessionSettings
        let voiceAction = action; let inputTarget = target; let hints = sessionHints; let context = sessionContext
        phase = .transcribing; onPanelChange?()
        if snapshot.interactionSounds { NSSound(named: "Pop")?.play() }
        let recordID = UUID(); let recordings = recordings
        operation = Task {
            defer { if sessionID == current { audio.cancel() } }
            // Saved before transcribing, so a failure can be retried from the history page.
            var saved: URL?
            if snapshot.recordingRetention != .off, let file = try? await audio.audioFile(),
               (try? recordings.save(file, as: recordID)) != nil { saved = recordings.url(for: recordID) }
            var heard = ""
            do {
                var raw: String
                if snapshot.speechBackend == .system {
                    raw = try SpeechTranscription.validatedText(await audio.systemTranscript())
                    if audio.usedPartialTranscript { notice = "系統未回傳完整結果，這次保留最後的辨識文字。" }
                    if RecognitionHints.isEcho(raw, hints: hints) { throw TalkError("沒有辨識到文字，請再試一次。") }
                } else {
                    let file: URL
                    if let saved { file = saved } else { file = try await audio.audioFile() }
                    raw = try await transcribeRecording(file, settings: snapshot, hints: hints)
                }
                try Task.checkCancellation(); guard sessionID == current else { return }
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TalkError("沒有辨識到文字，請再試一次。") }
                transcript = raw; heard = raw
                let cleaned = TextProcessing.clean(raw, settings: snapshot)
                var output = cleaned
                var aiFormatted = false
                if snapshot.requiresTextModel(for: voiceAction) && snapshot.textBackend != .basic {
                    phase = .processing
                    do {
                        var processed = try await process(text: cleaned, selection: inputTarget?.selection ?? "", action: voiceAction, settings: snapshot, context: context)
                        if let context, context.leaked(into: processed, transcript: cleaned) {
                            // The AI copied screen text; redo the cleanup without it.
                            processed = try await process(text: cleaned, selection: inputTarget?.selection ?? "", action: voiceAction, settings: snapshot)
                        }
                        output = voiceAction == .dictate ? try TextProcessing.checkedDictationOutput(processed, source: cleaned) : processed
                        if voiceAction == .dictate, (snapshot.dictationLayout ?? .automatic) == .automatic, ParagraphLayout.needsLayout(output),
                           let laidOut = try? await complete(prompt: ParagraphLayout.prompt(output), settings: snapshot) {
                            output = ParagraphLayout.accept(laidOut, original: output)
                        }
                        aiFormatted = true
                    }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        result = cleaned
                        if voiceAction == .dictate { notice = "AI 整理未完成，已保留原始辨識文字。" }
                        else if voiceAction == .hyday { notice = "AI 整理未完成，已記成一般列點。" }
                        else { throw error }
                    }
                }
                try Task.checkCancellation(); guard sessionID == current else { return }
                output = TextProcessing.formatOutput(output, action: voiceAction, settings: snapshot)
                result = output
                var delivered = false
                if voiceAction == .hyday {
                    // Kept as the result first, so a failed write still leaves the text to copy.
                    let formatted = aiFormatted ? HydayEntryFormatting.entry(output, time: HydayEntryFormatting.time(spokeAt)) : ""
                    let entry = HydayEntryFormatting.stamped(formatted.isEmpty ? HydayVault.bullet(output) : formatted,
                                                             time: HydayEntryFormatting.time(spokeAt)); result = entry
                    guard let root = hydayRoot else { throw TalkError("找不到 Hyday 資料夾，請到 Hyday 頁重新設定。") }
                    try await Task.detached(priority: .userInitiated) {
                        try HydayVault(root: root).appendToJournal(entry)
                    }.value
                    notice = notice.isEmpty ? "已記到 Hyday 今天的日誌。" : notice + " 已記到 Hyday 今天的日誌。"
                } else if snapshot.autoInsert && voiceAction != .ask {
                    let message: String
                    do {
                        message = try await TextInsertion.insert(output, target: inputTarget)
                        if voiceAction == .dictate { watchCorrections(of: output, at: inputTarget, settings: snapshot) }
                        delivered = true
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        try Task.checkCancellation(); guard sessionID == current else { return }
                        // Keep the panel up so the text can be copied by hand.
                        missedInsertion = true
                        message = error.localizedDescription
                    }
                    notice = notice.isEmpty ? message : notice + " " + message
                } else { notice = notice.isEmpty ? "文字已保留，可複製到需要的地方。" : notice }
                try Task.checkCancellation(); guard sessionID == current else { return }
                let place = voiceAction == .hyday ? "Hyday" : (inputTarget?.name ?? "結果區")
                usage.record(words: TextProcessing.wordCount(output), seconds: duration,
                             app: place, action: voiceAction); saveUsage()
                if snapshot.saveHistory {
                    history.insert(DictationRecord(id: recordID, rawText: raw, text: voiceAction == .hyday ? result : output, action: voiceAction, backend: snapshot.speechBackend,
                        duration: duration, destination: place), at: 0)
                    history = Array(history.prefix(200)); saveHistory()
                }
                if saved != nil, !snapshot.recordingRetention.keeps(failed: false, savesHistory: snapshot.saveHistory) { recordings.remove(recordID) }
                pruneRecordings()
                // Insertion or clipboard fallback finishes before hiding; the result remains available.
                phase = delivered ? .idle : .done; onPanelChange?()
                if voiceAction == .hyday {
                    // Confirm briefly, then get out of the way.
                    try? await Task.sleep(for: .seconds(2))
                    if sessionID == current, phase == .done { phase = .idle; onPanelChange?() }
                }
            } catch is CancellationError { if saved != nil { recordings.remove(recordID) } }
            catch {
                guard sessionID == current else { return }
                if saved != nil {
                    // Kept with the error, so the history page can run it again without speaking twice.
                    // Without saved history, the record holds only what a retry needs, never the words.
                    let words = snapshot.saveHistory ? heard : ""
                    history.insert(DictationRecord(id: recordID, rawText: words, text: words, action: voiceAction, backend: snapshot.speechBackend,
                        duration: duration, destination: voiceAction == .hyday ? "Hyday" : (inputTarget?.name ?? "結果區"),
                        failure: error.localizedDescription), at: 0)
                    history = Array(history.prefix(200)); saveHistory(); pruneRecordings()
                    fail(TalkError(error.localizedDescription + " 錄音已保留，可以重新處理。"))
                    failedRecordID = recordID
                } else { fail(error) }
            }
        }
    }

    /// Transcribes a recorded file, listening again without hints if the model recited them.
    private func transcribeRecording(_ file: URL, settings: TalkSettings, hints: [String]) async throws -> String {
        if settings.speechBackend == .system {
            let raw = try SpeechTranscription.validatedText(await AudioCapture.systemTranscript(of: file, settings: settings, hints: hints))
            if RecognitionHints.isEcho(raw, hints: hints) { throw TalkError("沒有辨識到文字，請再試一次。") }
            return raw
        }
        let key = settings.speechBackend == .api ? KeyStore.read("speech") : ""
        var raw = try await SpeechTranscription.transcribe(file: file, settings: settings, key: key, hints: hints)
        if RecognitionHints.isEcho(raw, hints: hints) {
            // The model recited the hint list instead of the speech; listen again without it.
            try Task.checkCancellation()
            raw = try await SpeechTranscription.transcribe(file: file, settings: settings, key: key, hints: [])
        }
        if RecognitionHints.isEcho(raw, hints: hints) { throw TalkError("沒有辨識到文字，請再試一次。") }
        return raw
    }

    // MARK: Saved recordings

    let recordings = RecordingStore(folder: LocalStore().directory.appendingPathComponent("Recordings", isDirectory: true))
    @Published private(set) var retrying: Set<UUID> = []
    /// The record of this session's failure, so the panel can offer to run it again.
    @Published private(set) var failedRecordID: UUID?
    var failedCount: Int { history.filter { $0.failure != nil }.count }
    @Published private(set) var recordingBytes: Int64 = 0

    /// Deletes expired recordings and those whose record is gone.
    func pruneRecordings() {
        let infos = history.map { RecordingInfo(id: $0.id, date: $0.date, failed: $0.failure != nil) }
        for id in settings.recordingRetention.stale(files: recordings.ids, records: infos) { recordings.remove(id) }
        recordingBytes = recordings.totalBytes
    }

    func removeAllRecordings() { recordings.removeAll(); recordingBytes = 0 }

    func hasRecording(_ record: DictationRecord) -> Bool { recordings.has(record.id) }

    /// Runs a saved recording through the current speech and text settings again.
    /// The result is copied, or written to today's Hyday journal for Hyday entries.
    func retryFailed() {
        guard let id = failedRecordID, let record = history.first(where: { $0.id == id }) else { return }
        retry(record, inPanel: true)
    }

    /// From the panel, the result goes where the dictation was meant to go, as it would have the first time.
    func retry(_ record: DictationRecord, inPanel: Bool = false) {
        guard recordings.has(record.id), !retrying.contains(record.id), !(inPanel && phase.busy) else { return }
        retrying.insert(record.id)
        let panelTarget = inPanel ? target : nil
        if inPanel { notice = ""; result = ""; missedInsertion = false; phase = .transcribing; onPanelChange?() }
        let snapshot = settings
        let hints = RecognitionHints.terms(dictionary: snapshot.dictionary, vocabulary: hydayVocabulary)
        Task {
            defer { retrying.remove(record.id) }
            var updated = record
            do {
                if record.action == .hyday, hydayRoot == nil { throw TalkError("找不到 Hyday 資料夾，請到 Hyday 頁重新設定。") }
                let raw = try await transcribeRecording(recordings.url(for: record.id), settings: snapshot, hints: hints)
                let cleaned = TextProcessing.clean(raw, settings: snapshot)
                var output = cleaned
                if snapshot.requiresTextModel(for: record.action) && snapshot.textBackend != .basic,
                   let processed = try? await process(text: cleaned, selection: "", action: record.action, settings: snapshot) {
                    output = record.action == .dictate ? ((try? TextProcessing.checkedDictationOutput(processed, source: cleaned)) ?? cleaned) : processed
                }
                output = TextProcessing.formatOutput(output, action: record.action, settings: snapshot)
                if record.action == .hyday, let root = hydayRoot {
                    let entry = HydayEntryFormatting.stamped(HydayVault.bullet(output), time: HydayEntryFormatting.time(record.date))
                    try await Task.detached(priority: .userInitiated) { try HydayVault(root: root).appendToJournal(entry) }.value
                    output = entry; notice = "已重新處理，並記到 Hyday 今天的日誌。"
                } else if inPanel, snapshot.autoInsert, record.action != .ask,
                          let message = try? await TextInsertion.insert(output, target: panelTarget) {
                    notice = "已重新處理。" + message
                } else if inPanel {
                    missedInsertion = record.action != .ask
                    notice = "已重新處理，文字已保留供複製。"
                } else { TextInsertion.copy(output); notice = "已重新處理，文字已複製。" }
                if inPanel { result = output; failedRecordID = nil; phase = missedInsertion || record.action == .ask ? .done : .idle; onPanelChange?() }
                updated.rawText = raw; updated.text = output; updated.backend = snapshot.speechBackend; updated.failure = nil
                if !snapshot.recordingRetention.keeps(failed: false, savesHistory: snapshot.saveHistory) { recordings.remove(record.id) }
            } catch {
                updated.failure = error.localizedDescription
                notice = "重新處理失敗：" + error.localizedDescription
                if inPanel { phase = .failed; onPanelChange?() }
            }
            if let index = history.firstIndex(where: { $0.id == record.id }) {
                // A retried failure stays only as long as text history is on.
                if updated.failure == nil && !snapshot.saveHistory { history.remove(at: index); recordings.remove(record.id) }
                else { history[index] = updated }
                saveHistory()
            }
            pruneRecordings()
        }
    }

    func cancel() {
        sessionID = UUID(); operation?.cancel(); operation = nil
        recordingTimer?.invalidate(); recordingTimer = nil; audio.cancel()
        phase = .idle; level = 0; elapsed = 0; transcript = ""; onPanelChange?()
    }
    func dismissPanel() { if phase.busy { cancel() } else { phase = .idle; onPanelChange?() } }
    func copyResult() { guard !result.isEmpty else { return }; TextInsertion.copy(result); notice = "已複製文字。" }
    func removeRecord(_ id: UUID) { history.removeAll { $0.id == id }; saveHistory(); recordings.remove(id); pruneRecordings() }
    func clearHistory() { history = []; saveHistory(); pruneRecordings() }
    func report(_ error: Error) { notice = error.localizedDescription }
    var todayRecords: [DictationRecord] { history.filter { Calendar.current.isDateInToday($0.date) } }

    private func fail(_ error: Error) {
        recordingTimer?.invalidate(); recordingTimer = nil; audio.cancel()
        notice = error.localizedDescription; phase = .failed; level = 0; onPanelChange?()
    }
    private func saveSettings() {
        do { try store.save(settings, to: "settings.json") } catch { notice = "設定未儲存。請確認磁碟空間與資料夾權限。" }
    }
    private func saveUsage() {
        do { try store.save(usage, to: "usage.json") } catch { notice += " 使用統計未儲存，請確認磁碟空間。" }
    }

    private func saveHistory() {
        do { try store.save(history, to: "history.json") } catch { notice += " 紀錄未儲存，請確認磁碟空間。" }
    }

    private func validate(_ settings: TalkSettings, action: VoiceAction) throws {
        switch settings.speechBackend {
        case .system: break
        case .whisper:
            guard localModels.engineReady(for: settings.whisperModel) else { throw TalkError("辨識引擎尚未就緒，請重新安裝 Hyday Talk。") }
            guard SpeechCLIConfiguration.isReadableModel(settings.whisperModel) else {
                throw TalkError("請在「語音辨識」下載並選擇本機模型。")
            }
        case .cli:
            try SpeechCLIConfiguration.validate(settings)
        case .api: try validateAPI(settings.speechAPI, account: "speech")
        }
        if action != .dictate && action != .hyday && settings.textBackend == .basic { throw TalkError("翻譯與提問需要文字 AI，請在「文字整理」選擇本機 AI 或 API Key。") }
        guard settings.requiresTextModel(for: action) else { return }
        if settings.textBackend == .local {
            guard !(settings.localTextModel ?? "").isEmpty else { throw TalkError("請在「文字整理」選擇本機文字模型。") }
        } else if settings.textBackend == .cli {
            guard FileManager.default.isExecutableFile(atPath: (settings.textCLIExecutable as NSString).expandingTildeInPath) else { throw TalkError("請先選擇文字 CLI 的可執行檔。") }
            _ = try CLIArguments.parse(settings.textCLIArguments)
        } else if settings.textBackend == .api { try validateAPI(settings.textAPI, account: "text") }
        else if settings.textBackend == .claude, claude() == nil {
            throw TalkError("找不到 Claude Code，請先安裝並登入 Claude Code，或改用其他整理方式。")
        }
    }

    /// One long-running Claude Code process, created once the `claude` command is installed.
    private func claude() -> ClaudeSession? {
        if let claudeSession { return claudeSession }
        guard let executable = ClaudeSession.discoverExecutable() else { return nil }
        claudeSession = ClaudeSession(executable: executable,
                                      workingDirectory: store.directory.appendingPathComponent("Claude", isDirectory: true))
        return claudeSession
    }
    private func validateAPI(_ api: APISettings, account: String) throws {
        let endpoint = try APIClient.endpoint(base: api.baseURL, path: "")
        guard !api.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw TalkError("請先填入模型名稱。") }
        if !["localhost", "127.0.0.1", "::1", "[::1]"].contains(endpoint.host ?? ""), KeyStore.read(account).isEmpty {
            throw TalkError("請先儲存 API Key。本機服務可以不填 Key。")
        }
    }

    private func process(text: String, selection: String, action: VoiceAction, settings: TalkSettings,
                         context: ScreenContext? = nil) async throws -> String {
        var notes: [HydayNote]?
        if action == .ask, settings.asksHydayNotes, settings.textBackend != .basic, let root = hydayRoot {
            notes = await HydaySearchService.notes(root: root, query: String([text, selection].filter { !$0.isEmpty }.joined(separator: " ").prefix(200)))
            try Task.checkCancellation()
        }
        let prompt = try TextProcessing.prompt(action: action, transcript: text, selection: selection, settings: settings, notes: notes, context: context)
        return settings.textBackend == .basic ? text : try await complete(prompt: prompt, settings: settings)
    }

    // MARK: Learning from corrections

    private struct PendingCorrection {
        let app: String
        let element: AXUIElement
        let pid: pid_t
        let location: Int
        let inserted: String
        let expires: Date
        /// Set once the caret moves inside the field, so edits made by someone else are not learned.
        var userEdited = false
    }

    private func watchCorrections(of inserted: String, at target: InputTarget?, settings: TalkSettings) {
        stopWatchingCorrections()
        guard settings.learnsFromCorrections, let target else { return }
        guard let element = target.element, let location = target.selectionRange?.location else {
            lastCorrectionCheck = CorrectionCheck(app: target.name, outcome: .unsupportedField); return
        }
        pendingCorrection = PendingCorrection(app: target.name, element: element, pid: target.pid, location: location, inserted: inserted,
                                              expires: Date().addingTimeInterval(120))
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkCorrectionsIfLeft() }
        }
        correctionTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func stopWatchingCorrections() {
        correctionTimer?.invalidate(); correctionTimer = nil; pendingCorrection = nil
    }

    private func checkCorrectionsIfLeft() {
        guard let pending = pendingCorrection else { stopWatchingCorrections(); return }
        if Date() > pending.expires {
            lastCorrectionCheck = CorrectionCheck(app: pending.app, outcome: .noEdit); stopWatchingCorrections(); return
        }
        guard TextInsertion.isEditing(pending.element, pid: pending.pid) else { checkCorrections(); return }
        if let caret = TextInsertion.caretLocation(pending.element), caret != pending.location + pending.inserted.utf16.count {
            pendingCorrection?.userEdited = true
        }
    }

    /// Return often sends and clears a chat or terminal box, so the field is read before the key reaches it.
    private func checkCorrectionsBeforeReturn() {
        guard let pending = pendingCorrection, TextInsertion.isEditing(pending.element, pid: pending.pid) else { return }
        checkCorrections()
    }

    /// Reads the field once, after the user left it or started the next dictation; unreadable fields are skipped silently.
    private func checkCorrections() {
        guard var pending = pendingCorrection else { return }
        stopWatchingCorrections()
        // The next fn press can arrive between samples; check the caret one last time.
        if TextInsertion.isEditing(pending.element, pid: pending.pid),
           let caret = TextInsertion.caretLocation(pending.element), caret != pending.location + pending.inserted.utf16.count {
            pending.userEdited = true
        }
        guard Date() <= pending.expires, pending.userEdited else {
            lastCorrectionCheck = CorrectionCheck(app: pending.app, outcome: .noEdit); return
        }
        guard let following = TextInsertion.readBack(pending.element, from: pending.location, length: pending.inserted.utf16.count + 200) else {
            lastCorrectionCheck = CorrectionCheck(app: pending.app, outcome: .unreadable); return
        }
        let corrections = CorrectionFinder.find(inserted: pending.inserted, following: following)
        guard !corrections.isEmpty else { lastCorrectionCheck = CorrectionCheck(app: pending.app, outcome: .noCorrection); return }
        let app = pending.app
        let snapshot = settings
        // Learning follows the order of the user's edits, not the order the AI answers in.
        let previous = correctionTask
        correctionTask = Task { [weak self] in
            await previous?.value
            var learned = 0, typos = 0, failed = 0
            for correction in corrections {
                // Without a text AI only English words, numbers and acronyms are safe to learn.
                if snapshot.textBackend == .basic {
                    guard CorrectionJudge.learnableWithoutAI(correction.corrected) else { typos += 1; continue }
                    guard !Task.isCancelled, let model = self, model.settings.learnsFromCorrections else { break }
                    DictionaryLearning.learn(correction, into: &model.settings); learned += 1; continue
                }
                guard let prompt = try? CorrectionJudge.prompt(for: correction),
                      let answer = try? await self?.complete(prompt: prompt, settings: snapshot) else { failed += 1; continue }
                guard CorrectionJudge.isTerm(answer) else { typos += 1; continue }
                guard !Task.isCancelled, let self, self.settings.learnsFromCorrections else { return }
                DictionaryLearning.learn(correction, into: &self.settings); learned += 1
            }
            guard !Task.isCancelled, let self else { return }
            self.lastCorrectionCheck = CorrectionCheck(app: app, outcome: learned > 0 ? .learned(learned)
                : (typos > 0 ? .notTerms(typos) : .judgeFailed))
        }
    }

    private func complete(prompt: String, settings: TalkSettings) async throws -> String {
        switch settings.textBackend {
        case .basic: throw TalkError("基礎整理沒有文字 AI。")
        case .local: return try await LocalTextClient.complete(prompt: prompt, model: settings.localTextModel ?? "")
        case .api: return try await APIClient.complete(prompt: prompt, settings: settings.textAPI, key: KeyStore.read("text"))
        case .claude:
            guard let session = claude() else { throw TalkError("找不到 Claude Code，請先安裝並登入 Claude Code。") }
            return try await session.complete(prompt: prompt, model: settings.claudeModel.rawValue)
        case .cli:
            let arguments = CLIArguments.expand(try CLIArguments.parse(settings.textCLIArguments), values: ["{prompt}": prompt])
            let output = try await ProcessRunner.run(executable: settings.textCLIExecutable, arguments: arguments, input: prompt, timeout: 120)
            guard !output.isEmpty else { throw TalkError("文字 CLI 未回傳內容。請設定工具將結果寫入標準輸出。") }
            return output
        }
    }
}

