import Foundation

public enum InputApplicationRouting {
    public static func targetPID(frontmostPID: Int32?, recorderPID: Int32,
                                 previousExternalPID: Int32?) -> Int32? {
        guard let frontmostPID, frontmostPID > 0 else { return nil }
        if frontmostPID != recorderPID { return frontmostPID }
        guard let previousExternalPID, previousExternalPID > 0, previousExternalPID != recorderPID else { return nil }
        return previousExternalPID
    }

    /// Apps that draw their own text and report only a window as the focused element,
    /// so no text field can be detected. Pasting still works in them.
    static let windowOnlyPasteApps: Set<String> = ["dev.herdr.app"]

    public static func acceptsPasteWithoutTextField(bundleID: String?, focusedRole: String) -> Bool {
        guard let bundleID, focusedRole == "AXWindow" else { return false }
        return windowOnlyPasteApps.contains(bundleID)
    }
}
