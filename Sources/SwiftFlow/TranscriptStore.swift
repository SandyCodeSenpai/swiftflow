import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct TranscriptEntry: Identifiable, Equatable {
    let id: Int64
    let createdAt: Date
    let duration: Double
    let raw: String
    let cleaned: String?

    /// What the user actually got pasted — cleaned when available, else raw.
    var displayText: String {
        if let cleaned, !cleaned.isEmpty { return cleaned }
        return raw
    }
}

/// Persists every dictation to ~/.swiftflow/history.db (SQLite, WAL mode).
/// All access happens on the main thread — inserts are sub-millisecond and
/// the UI observes `entries` directly.
final class TranscriptStore: ObservableObject {
    static let shared = TranscriptStore()

    @Published private(set) var entries: [TranscriptEntry] = []
    private var db: OpaquePointer?

    private init() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftflow/history.db")
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            Log.write("history db open FAILED: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_close(db)
            db = nil
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("""
            CREATE TABLE IF NOT EXISTS transcripts(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at REAL NOT NULL,
                duration REAL NOT NULL DEFAULT 0,
                raw TEXT NOT NULL,
                cleaned TEXT
            )
            """)
        entries = fetchAll()
    }

    func save(raw: String, cleaned: String?, duration: Double, at date: Date) {
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO transcripts (created_at, duration, raw, cleaned) VALUES (?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.write("history insert prepare FAILED: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, duration)
        sqlite3_bind_text(stmt, 3, raw, -1, SQLITE_TRANSIENT)
        if let cleaned {
            sqlite3_bind_text(stmt, 4, cleaned, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            Log.write("history insert FAILED: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        let entry = TranscriptEntry(id: sqlite3_last_insert_rowid(db), createdAt: date,
                                    duration: duration, raw: raw, cleaned: cleaned)
        entries.insert(entry, at: 0)
    }

    func delete(_ id: Int64) {
        exec("DELETE FROM transcripts WHERE id = \(id)")
        entries.removeAll { $0.id == id }
    }

    func clearAll() {
        exec("DELETE FROM transcripts")
        entries.removeAll()
    }

    private func fetchAll() -> [TranscriptEntry] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, created_at, duration, raw, cleaned FROM transcripts ORDER BY created_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var result: [TranscriptEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let cleaned = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            result.append(TranscriptEntry(
                id: sqlite3_column_int64(stmt, 0),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                duration: sqlite3_column_double(stmt, 2),
                raw: sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "",
                cleaned: cleaned
            ))
        }
        return result
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            Log.write("history db exec FAILED: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
}
