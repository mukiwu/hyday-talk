import Foundation

/// Text around the cursor when recording starts, given to the text AI as reference only.
/// It is never inserted or saved.
public struct ScreenContext: Equatable, Sendable {
    public static let beforeLimit = 800
    public static let afterLimit = 200
    public static let defaultExcludedApps = ["1Password", "鑰匙圈存取", "Keychain Access", "Passwords", "密碼"]

    public let app: String
    public let windowTitle: String
    public let before: String
    public let after: String

    /// `cursor` counts characters from the start of `text`; apps without readable text pass nil.
    public init(app: String, windowTitle: String, text: String?, cursor: Int?) {
        self.app = app; self.windowTitle = windowTitle
        guard let text, let cursor else { before = ""; after = ""; return }
        let index = text.index(text.startIndex, offsetBy: min(max(cursor, 0), text.count))
        before = String(text[..<index].suffix(Self.beforeLimit))
        after = String(text[index...].prefix(Self.afterLimit))
    }

    public var isEmpty: Bool { app.isEmpty && windowTitle.isEmpty && before.isEmpty && after.isEmpty }

    /// True when the output carries a stretch of screen text that the user never said,
    /// which means the AI copied or continued the screen instead of only borrowing spellings.
    public func leaked(into output: String, transcript: String, window: Int = 10) -> Bool {
        let source = Array(Self.letters(before + after)), said = Self.letters(transcript), written = Self.letters(output)
        guard source.count >= window else { return false }
        for start in 0...(source.count - window) {
            let piece = String(source[start..<start + window])
            if written.contains(piece) && !said.contains(piece) { return true }
        }
        return false
    }

    private static func letters(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).contains($0) }.map(Character.init))
    }

    /// The window title is free text from another app, so it is reduced to terms like the rest.
    /// Capitalised English words, acronyms and product names near the cursor. Small models copy
    /// whole screen text into their output, so only these spellings are handed to the AI.
    public var terms: [String] {
        let regex = try! NSRegularExpression(pattern: "[A-Za-z][A-Za-z0-9+#]*(?:[.-][A-Za-z0-9+#]+)*")
        let text = windowTitle + " " + before + " " + after
        var seen = Set<String>(); var result: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let word = String(text[range])
            guard word.count >= 2, word.contains(where: \.isUppercase), seen.insert(word.lowercased()).inserted else { continue }
            result.append(word)
            if result.count == 40 { break }
        }
        return result
    }

    var payload: [String: Any] {
        ["app": app, "terms": terms]
    }
}

public extension TalkSettings {
    /// Local text AI keeps screen text on this Mac, so it is on by default; an API or Claude sends it out, so it is off.
    var readsScreenContext: Bool {
        get { readScreenContext ?? (textBackend != .api && textBackend != .claude) }
        set { readScreenContext = newValue }
    }

    var screenContextExcludedApps: [String] {
        get { screenContextExcluded ?? ScreenContext.defaultExcludedApps }
        set { screenContextExcluded = newValue }
    }

    func shouldReadScreenContext(for action: VoiceAction, app: String) -> Bool {
        guard readsScreenContext, action != .ask, textBackend != .basic, requiresTextModel(for: action) else { return false }
        return !screenContextExcludedApps.contains { $0.caseInsensitiveCompare(app) == .orderedSame }
    }
}
