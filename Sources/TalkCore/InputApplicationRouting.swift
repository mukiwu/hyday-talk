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
