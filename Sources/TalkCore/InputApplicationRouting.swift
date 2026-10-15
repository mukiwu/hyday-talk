import Foundation

public enum InputApplicationRouting {
    public static func targetPID(frontmostPID: Int32?, recorderPID: Int32,
                                 previousExternalPID: Int32?) -> Int32? {
        guard let frontmostPID, frontmostPID > 0 else { return nil }
        if frontmostPID != recorderPID { return frontmostPID }
        guard let previousExternalPID, previousExternalPID > 0, previousExternalPID != recorderPID else { return nil }
        return previousExternalPID
    }
}

/// Finds the input field to dictate into. Electron apps such as HyperFrames stop reporting their
/// focused element about two seconds after activation while the caret stays in the field, but the
/// field itself still says it has focus; so the field last reported by the app is remembered and asked.
public enum FocusMemory {
    /// The field the app reports as focused, else the remembered one while it still has focus.
    public static func field<Field>(reported: Field?, remembered: Field?, rememberedHasFocus: @autoclosure () -> Bool) -> Field? {
        if let reported { return reported }
        guard let remembered, rememberedHasFocus() else { return nil }
        return remembered
    }

    /// Keeps the last reported field while the same app reports none, since Electron apps go quiet
    /// about focus a few seconds after activation; another app starts over.
    public static func remembered<Field>(previous: Field?, previousPID: Int32?, reported: Field?, pid: Int32) -> Field? {
        reported ?? (previousPID == pid ? previous : nil)
    }
}
