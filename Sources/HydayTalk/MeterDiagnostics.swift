import OSLog

/// Logs one summary line per recording for the panel's level meter, which now and then shows a flat line.
/// Read it with: log show --last 1h --predicate 'subsystem == "tw.muki.hyday-talk" AND category == "Meter"'
/// Few levels or a low maximum point at the microphone; normal levels with few recording ticks point at the panel.
@MainActor
final class MeterDiagnostics {
    static let shared = MeterDiagnostics()
    private let logger = Logger(subsystem: "tw.muki.hyday-talk", category: "Meter")
    private var levels = 0, maxLevel = 0.0, ticks = 0, recordingTicks = 0

    func start(sampleRate: Double, channels: UInt32) {
        levels = 0; maxLevel = 0; ticks = 0; recordingTicks = 0
        logger.notice("Recording input rate=\(sampleRate) channels=\(channels)")
    }
    func record(level: Double) { levels += 1; maxLevel = max(maxLevel, level) }
    func recordTick(recording: Bool) { ticks += 1; if recording { recordingTicks += 1 } }
    func report(elapsed: Double) {
        logger.notice("Recording finished seconds=\(elapsed) levels=\(self.levels) max=\(self.maxLevel) ticks=\(self.ticks) recordingTicks=\(self.recordingTicks)")
    }
}
