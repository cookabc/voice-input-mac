import Foundation
import SQLite3

/// Persists transcription session records in a local SQLite database
/// at `~/.murmur/history.db`.
final class HistoryStore {
    static let shared = HistoryStore()

    struct Record: Identifiable {
        let id: Int64
        let timestamp: Date
        let durationSec: Double
        let textLength: Int
        let mode: String       // "manual" or "auto"
        let polished: Bool
        let success: Bool
    }

    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.murmur"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        dbPath = "\(dir)/history.db"
        openDB()
        createTable()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Write

    func record(
        durationSec: Double,
        textLength: Int,
        mode: String,
        polished: Bool,
        success: Bool
    ) {
        let sql = """
            INSERT INTO sessions (timestamp, duration_sec, text_length, mode, polished, success)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, durationSec)
        sqlite3_bind_int(stmt, 3, Int32(textLength))
        sqlite3_bind_text(stmt, 4, (mode as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 5, polished ? 1 : 0)
        sqlite3_bind_int(stmt, 6, success ? 1 : 0)
        sqlite3_step(stmt)
    }

    // MARK: - Read

    func recentRecords(limit: Int = 50) -> [Record] {
        let sql = "SELECT id, timestamp, duration_sec, text_length, mode, polished, success FROM sessions ORDER BY timestamp DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var results = [Record]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Record(
                id: sqlite3_column_int64(stmt, 0),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                durationSec: sqlite3_column_double(stmt, 2),
                textLength: Int(sqlite3_column_int(stmt, 3)),
                mode: String(cString: sqlite3_column_text(stmt, 4)),
                polished: sqlite3_column_int(stmt, 5) != 0,
                success: sqlite3_column_int(stmt, 6) != 0
            ))
        }
        return results
    }

    struct Stats {
        let totalSessions: Int
        let last7DaysSessions: Int
        let failureRate: Double
        let avgDuration: Double
    }

    func stats() -> Stats {
        let total = queryInt("SELECT COUNT(*) FROM sessions")
        let sevenDaysAgo = Date().timeIntervalSince1970 - 7 * 86400
        let recent = queryInt("SELECT COUNT(*) FROM sessions WHERE timestamp > \(sevenDaysAgo)")
        let failures = queryInt("SELECT COUNT(*) FROM sessions WHERE success = 0")
        let avgDur = queryDouble("SELECT AVG(duration_sec) FROM sessions")
        return Stats(
            totalSessions: total,
            last7DaysSessions: recent,
            failureRate: total > 0 ? Double(failures) / Double(total) : 0,
            avgDuration: avgDur
        )
    }

    // MARK: - Export

    func exportCSV() -> String {
        var csv = "id,timestamp,duration_sec,text_length,mode,polished,success\n"
        let records = recentRecords(limit: 10000)
        let fmt = ISO8601DateFormatter()
        for r in records {
            csv += "\(r.id),\(fmt.string(from: r.timestamp)),\(r.durationSec),\(r.textLength),\(r.mode),\(r.polished),\(r.success)\n"
        }
        return csv
    }

    // MARK: - Private

    private func openDB() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            fputs("[HistoryStore] Failed to open \(dbPath)\n", stderr)
        }
    }

    private func createTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                duration_sec REAL NOT NULL DEFAULT 0,
                text_length INTEGER NOT NULL DEFAULT 0,
                mode TEXT NOT NULL DEFAULT 'manual',
                polished INTEGER NOT NULL DEFAULT 0,
                success INTEGER NOT NULL DEFAULT 1
            )
            """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func queryInt(_ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    private func queryDouble(_ sql: String) -> Double {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_double(stmt, 0) : 0
    }
}
