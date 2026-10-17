import XCTest
@testable import TalkCore

final class RecordingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func testOffKeepsNothingEvenAfterAFailure() {
        XCTAssertFalse(RecordingRetention.off.keeps(failed: false, savesHistory: true))
        XCTAssertFalse(RecordingRetention.off.keeps(failed: true, savesHistory: true))
    }

    func testFailedOnlyDropsASuccessfulRecordingButKeepsAFailedOne() {
        XCTAssertFalse(RecordingRetention.failedOnly.keeps(failed: false, savesHistory: true))
        XCTAssertTrue(RecordingRetention.failedOnly.keeps(failed: true, savesHistory: true))
    }

    func testNoHistoryKeepsOnlyFailedRecordings() {
        XCTAssertFalse(RecordingRetention.days(7).keeps(failed: false, savesHistory: false))
        XCTAssertTrue(RecordingRetention.days(7).keeps(failed: true, savesHistory: false))
        XCTAssertTrue(RecordingRetention.forever.keeps(failed: false, savesHistory: true))
    }

    func testDaysExpireOnlySuccessfulRecordingsOlderThanTheLimit() {
        let retention = RecordingRetention.days(3)
        XCTAssertFalse(retention.expired(recordedAt: daysAgo(2.9), failed: false, now: now))
        XCTAssertTrue(retention.expired(recordedAt: daysAgo(3.1), failed: false, now: now))
        XCTAssertFalse(retention.expired(recordedAt: daysAgo(30), failed: true, now: now))
    }

    func testForeverNeverExpires() {
        XCTAssertFalse(RecordingRetention.forever.expired(recordedAt: daysAgo(3650), failed: false, now: now))
    }

    func testStaleFilesAreExpiredOrWithoutARecord() {
        let kept = UUID(), old = UUID(), failedOld = UUID(), orphan = UUID()
        let records = [
            RecordingInfo(id: kept, date: daysAgo(1), failed: false),
            RecordingInfo(id: old, date: daysAgo(10), failed: false),
            RecordingInfo(id: failedOld, date: daysAgo(10), failed: true),
        ]
        let stale = RecordingRetention.days(7).stale(files: [kept, old, failedOld, orphan], records: records, now: now)
        XCTAssertEqual(Set(stale), [old, orphan])
    }

    func testRetentionSurvivesSavingSettings() throws {
        var settings = TalkSettings()
        XCTAssertEqual(settings.recordingRetention, .days(7))
        settings.recordingRetention = .days(14)
        let decoded = try JSONDecoder().decode(TalkSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.recordingRetention, .days(14))
    }

    func testRecordsFromEarlierVersionsDecodeAsSuccessful() throws {
        let record = DictationRecord(rawText: "a", text: "a", action: .dictate, backend: .whisper, duration: 1, destination: "x")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        json.removeValue(forKey: "failure")
        let decoded = try JSONDecoder().decode(DictationRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.failure)
    }
}
