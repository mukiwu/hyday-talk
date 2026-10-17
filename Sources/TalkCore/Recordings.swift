import Foundation

/// How long dictation audio stays on this Mac, so a failed transcription can run again
/// without speaking twice. Failed recordings wait for a retry or a manual delete.
public enum RecordingRetention: Codable, Hashable, Sendable {
    case off, failedOnly, days(Int), forever

    public static let recommended = RecordingRetention.days(7)

    public var title: String {
        switch self {
        case .off: return "不保留"
        case .failedOnly: return "只保留失敗的"
        case .days(let days): return "\(days) 天"
        case .forever: return "永久"
        }
    }

    /// Whether a recording stays after it is processed. Without saved history there is no
    /// record to replay a success from, so only failures are kept.
    public func keeps(failed: Bool, savesHistory: Bool) -> Bool {
        switch self {
        case .off: return false
        case .failedOnly: return failed
        case .days, .forever: return failed || savesHistory
        }
    }

    public func expired(recordedAt date: Date, failed: Bool, now: Date = Date()) -> Bool {
        guard !failed, case .days(let days) = self else { return false }
        return now.timeIntervalSince(date) > Double(days) * 86_400
    }

    /// Recording files to delete: expired ones and any without a record left to replay them.
    public func stale(files: [UUID], records: [RecordingInfo], now: Date = Date()) -> [UUID] {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return files.filter { id in
            guard let record = byID[id] else { return true }
            return expired(recordedAt: record.date, failed: record.failed, now: now)
        }
    }
}

public struct RecordingInfo: Sendable {
    public let id: UUID
    public let date: Date
    public let failed: Bool
    public init(id: UUID, date: Date, failed: Bool) { self.id = id; self.date = date; self.failed = failed }
}

/// Recordings saved as 16 kHz mono WAV, named by their dictation record's id.
public struct RecordingStore: Sendable {
    public let folder: URL
    public init(folder: URL) { self.folder = folder }

    public func url(for id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".wav") }
    public func has(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(for: id).path) }

    public func save(_ file: URL, as id: UUID) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = url(for: id)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: file, to: target)
    }

    public func remove(_ id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }

    public var ids: [UUID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { $0.hasSuffix(".wav") ? UUID(uuidString: String($0.dropLast(4))) : nil }
    }

    public var totalBytes: Int64 {
        ids.reduce(0) { sum, id in
            sum + ((try? FileManager.default.attributesOfItem(atPath: url(for: id).path)[.size] as? Int64) ?? 0)
        }
    }

    public func removeAll() { ids.forEach(remove) }
}
