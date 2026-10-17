import AppKit
import TalkCore
import OSLog

struct InputTarget {
    let pid: pid_t
    let name: String
    let element: AXUIElement?
    let selection: String
    let selectionRange: CFRange?
    let editable: Bool
    let secure: Bool
}

@MainActor
enum TextInsertion {
    private static let logger = Logger(subsystem: "tw.muki.hyday-talk", category: "TextInsertion")
    private static var previousExternalApplication: NSRunningApplication?
    private static var previousExternalElement: AXUIElement?
    private static var activationObserver: NSObjectProtocol?
    private static var focusTimer: Timer?

    static func startTracking() {
        guard activationObserver == nil else { return }
        if let app = NSWorkspace.shared.frontmostApplication { remember(app) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { remember(app) }
        }
        // Remember the foreground app's field for when our own window comes forward.
        // Retain only its AX reference; selected text is read only when a recording starts.
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated {
                if let app = NSWorkspace.shared.frontmostApplication { remember(app) }
            }
        }
        focusTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    static func stopTracking() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil; focusTimer?.invalidate(); focusTimer = nil
        forgetDestination()
    }

    static func forgetDestination() { previousExternalApplication = nil; previousExternalElement = nil }

    private static var accessibleApps: Set<pid_t> = []

    /// Electron and other Chromium apps build their accessibility tree only after a
    /// client sets AXManualAccessibility; until then they report no focused field.
    /// Other apps ignore the attribute.
    private static func enableAccessibility(_ pid: pid_t) {
        guard !accessibleApps.contains(pid) else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        let error = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        logger.notice("AXManualAccessibility pid=\(pid) AXError=\(error.rawValue)")
        // Apps that do not support the attribute will not start to; stop asking them.
        if error == .success || error == .attributeUnsupported || error == .illegalArgument { accessibleApps.insert(pid) }
    }

    private static func remember(_ app: NSRunningApplication) {
        if app.processIdentifier != ProcessInfo.processInfo.processIdentifier && !app.isTerminated {
            enableAccessibility(app.processIdentifier)
            previousExternalElement = focusedElement(pid: app.processIdentifier)
            previousExternalApplication = app
        }
    }

    static func capture() -> InputTarget? {
        let previousPID = previousExternalApplication?.isTerminated == false
            ? previousExternalApplication?.processIdentifier : nil
        guard let pid = InputApplicationRouting.targetPID(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            recorderPID: ProcessInfo.processInfo.processIdentifier, previousExternalPID: previousPID),
              let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let cachedElement = previousExternalApplication?.processIdentifier == pid ? previousExternalElement : nil
        let element = field(pid: app.processIdentifier, remembered: cachedElement)
        let role = element.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? ""
        let subrole = element.flatMap { attribute($0, kAXSubroleAttribute) as? String } ?? ""
        var settable = DarwinBoolean(false)
        if let element { AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) }
        let secure = subrole == kAXSecureTextFieldSubrole
        let editable = settable.boolValue || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
        logger.notice("Capture foreground=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) target=\(pid) role=\(role, privacy: .public) cached=\(cachedElement != nil) editable=\(editable) secure=\(secure)")
        return InputTarget(pid: app.processIdentifier, name: app.localizedName ?? "目前 App", element: element,
            selection: secure ? "" : (element.flatMap { attribute($0, kAXSelectedTextAttribute) as? String } ?? ""),
            selectionRange: element.flatMap(range), editable: editable, secure: secure)
    }

    /// Reads the app, window title and text around the cursor for the text AI to refer to.
    /// Password fields give nothing; apps without readable text give only their name and title.
    static func screenContext(of target: InputTarget?) -> ScreenContext? {
        guard let target, !target.secure else { return nil }
        let app = AXUIElementCreateApplication(target.pid)
        let window = attribute(app, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
        let title = window.flatMap { attribute($0, kAXTitleAttribute) as? String } ?? ""
        var text: String?; var cursor: Int?
        if let element = target.element, let value = attribute(element, kAXValueAttribute) as? String,
           let location = target.selectionRange?.location, location >= 0 {
            // Accessibility ranges count UTF-16 units; ScreenContext counts characters.
            let units = (value as NSString).length
            text = value; cursor = (value as NSString).substring(to: min(location, units)).count
        }
        return ScreenContext(app: target.name, windowTitle: title, text: text, cursor: cursor)
    }

    static func insert(_ text: String, target: InputTarget?) async throws -> String {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw TalkError("文字已保留。開啟輔助使用權限後，才能自動輸入。") }
        guard let target, !target.secure, target.editable, let element = target.element else {
            throw TalkError("文字已保留。請在一般文字輸入框使用，或複製結果。")
        }
        // Recorder controls may bring our main window forward. Return only from
        // our own app, never take focus away from a different external app.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated,
                  app.activate(options: []) else {
                throw TalkError("無法返回原本的 App，文字已保留供複製。")
            }
            for _ in 0..<10 {
                try Task.checkCancellation()
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid { break }
                try await Task.sleep(nanoseconds: 30_000_000)
            }
        }
        try Task.checkCancellation()
        let current = field(pid: target.pid, remembered: element)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              let current, CFEqual(element, current) else {
            throw TalkError("你已切換輸入位置，文字已保留供複製。")
        }
        if let problem = InsertionCheck.problem(before: target.selectionRange, after: range(current), beforeSelection: target.selection,
                                                afterSelection: attribute(current, kAXSelectedTextAttribute) as? String ?? "") {
            throw TalkError(problem)
        }
        // Always use the editor's paste command. AX setters can report success
        // on a terminal's hidden textarea without sending an input/paste event.
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw TalkError("無法送出貼上操作。請複製結果。")
        }
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                item.data(forType: type).map { (type, $0) }
            }
        }
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap); up.post(tap: .cgAnnotatedSessionEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            let items = saved.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        return "已送出貼上指令至 \(target.name)"
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    /// The app's focused field; while our own window is in front, the field remembered before it.
    private static func field(pid: pid_t, remembered: AXUIElement?) -> AXUIElement? {
        if let focused = focusedElement(pid: pid) { return focused }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? remembered : nil
    }

    private static func focusedElement(pid: pid_t) -> AXUIElement? {
        var focused: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        if error != .success { logger.debug("Focused element pid=\(pid) AXError=\(error.rawValue)") }
        if focused == nil {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.2)
            _ = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        }
        guard let value = focused,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == pid else { return nil }
        return element
    }
    /// Text of the field from the insertion point, or nil when the app does not expose its value.
    static func readBack(_ element: AXUIElement, from location: Int, length: Int) -> String? {
        guard let value = attribute(element, kAXValueAttribute) as? String else { return nil }
        let utf16 = value.utf16
        guard location >= 0, location <= utf16.count else { return nil }
        let start = utf16.index(utf16.startIndex, offsetBy: location)
        var end = utf16.index(start, offsetBy: min(length, utf16.count - location))
        // Never cut a surrogate pair, or the slice cannot become a String.
        if end < utf16.endIndex, UTF16.isTrailSurrogate(utf16[end]), end > start { end = utf16.index(before: end) }
        return String(utf16[start..<end])
    }

    static func caretLocation(_ element: AXUIElement) -> Int? { range(element).map { Int($0.location) } }

    static func isEditing(_ element: AXUIElement, pid: pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = field(pid: pid, remembered: element) else { return false }
        return CFEqual(element, current)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func range(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange(); return AXValueGetValue(ax, .cfRange, &range) ? range : nil
    }
}
