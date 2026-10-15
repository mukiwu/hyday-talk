import CoreFoundation

/// Decides whether pasting is still safe after the user finished speaking.
public enum InsertionCheck {
    /// Nil when pasting may go ahead. A different selection would be overwritten, so it keeps the text;
    /// a caret whose location moved without a selection is not a reason, since terminals and chat pages
    /// count it from the start of all their text and shift it whenever output appears above the field.
    public static func problem(before: CFRange?, after: CFRange?, beforeSelection: String, afterSelection: String) -> String? {
        if beforeSelection != afterSelection { return "選取文字已改變，結果已保留供複製。" }
        if let before, let after, before.length != after.length { return "游標或選取範圍已改變，文字已保留供複製。" }
        return nil
    }
}
