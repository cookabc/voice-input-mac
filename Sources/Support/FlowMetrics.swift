import Foundation

/// Lightweight flow-timing tracker.
/// Records wall-clock durations for each pipeline stage in a single session.
@MainActor
final class FlowMetrics: ObservableObject {
    struct StageRecord: Identifiable {
        let id = UUID()
        let stage: String
        let startedAt: Date
        var endedAt: Date?
        var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
        var outcome: Outcome = .inProgress

        enum Outcome: String { case inProgress, success, failure }
    }

    struct SessionSummary {
        let sessionId: UUID
        let startedAt: Date
        let endedAt: Date
        let totalDuration: TimeInterval
        let stages: [StageRecord]
        let outcome: StageRecord.Outcome
    }

    @Published private(set) var currentSession: UUID?
    @Published private(set) var stages: [StageRecord] = []

    private var sessionStart: Date?

    func beginSession() {
        currentSession = UUID()
        sessionStart = Date()
        stages = []
    }

    func beginStage(_ name: String) {
        // End any in-progress stage first.
        endCurrentStage(outcome: .success)
        stages.append(StageRecord(stage: name, startedAt: Date()))
    }

    func endCurrentStage(outcome: StageRecord.Outcome) {
        guard !stages.isEmpty, stages[stages.count - 1].endedAt == nil else { return }
        stages[stages.count - 1].endedAt = Date()
        stages[stages.count - 1].outcome = outcome
    }

    func endSession(outcome: StageRecord.Outcome = .success) -> SessionSummary? {
        endCurrentStage(outcome: outcome)
        guard let sid = currentSession, let start = sessionStart else { return nil }
        let end = Date()
        let summary = SessionSummary(
            sessionId: sid,
            startedAt: start,
            endedAt: end,
            totalDuration: end.timeIntervalSince(start),
            stages: stages,
            outcome: outcome
        )
        // Log to stderr for local diagnostics.
        let stageLines = summary.stages.map { s in
            let dur = s.duration.map { String(format: "%.2fs", $0) } ?? "—"
            return "  \(s.stage): \(dur) [\(s.outcome.rawValue)]"
        }.joined(separator: "\n")
        fputs("[FlowMetrics] Session \(sid) — \(String(format: "%.2fs", summary.totalDuration)) [\(outcome.rawValue)]\n\(stageLines)\n", stderr)
        currentSession = nil
        sessionStart = nil
        return summary
    }

    /// Formatted string for display in diagnostics UI.
    var stageSummaryText: String {
        guard !stages.isEmpty else { return "No active session" }
        return stages.map { s in
            let dur = s.duration.map { String(format: "%.1fs", $0) } ?? "…"
            return "\(s.stage) \(dur)"
        }.joined(separator: " → ")
    }
}
