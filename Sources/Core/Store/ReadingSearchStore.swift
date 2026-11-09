import Foundation
import Combine
import SQLite3

/// Searchable text from pages the reader actually loaded, not an offline thread archive.
final class ReadingSearchStore: ObservableObject {
    static let shared = ReadingSearchStore()

    struct Hit: Identifiable {
        var postId: Int
        var page: Int
        var onlyPo: Bool
        var excerpt: String
        // Search rows must not share the reader's integer scroll anchors.
        var id: String { "search-hit:\(postId)" }
    }

    struct Match {
        var hits: [Hit]
        var postId: Int { hits[0].postId }
        var page: Int { hits[0].page }
        var onlyPo: Bool { hits[0].onlyPo }
        var excerpt: String { hits[0].excerpt }
        var count: Int { hits.count }
    }

    struct SearchResult {
        var matches: [Int: Match] = [:]
        var blockedThreads: Set<Int> = []
    }

    enum ContentScope: String, CaseIterable, Identifiable {
        case all = "全部内容"
        case threads = "主串"
        case replies = "回复"

        var id: Self { self }
    }

    struct Filter: Equatable {
        var scope: ContentScope = .all
        var forumId: Int? = nil

        func includes(postId: Int, threadId: Int, forumId: Int?) -> Bool {
            if let selectedForum = self.forumId, forumId != selectedForum { return false }
            switch scope {
            case .all: return true
            case .threads: return postId == threadId
            case .replies: return postId != threadId
            }
        }
    }

    struct BackupRow: Codable, Equatable {
        var threadId: Int
        var postId: Int
        var page: Int
        var onlyPo: Bool
        var body: String
        var searchable: String
        var recordedAt: Date
        var userHash: String? = nil
        var forumId: Int? = nil
        var name: String? = nil
        var title: String? = nil
    }

    @Published private(set) var revision = 0
    @Published private(set) var writeError: String?

    private let queue = DispatchQueue(label: "xd.reading-search", qos: .utility)
    private let path = AppPaths.file("reading-search.sqlite").path
    // Accessed only on queue. The singleton keeps this connection for the app lifetime.
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {}

    func record(main: XDPost, replies: [XDPost], page: Int, onlyPo: Bool) {
        guard SettingsStore.shared.recordBrowsing else { return }
        let posts = [main] + replies.filter { $0.id > 0 && $0.kind != .tip }
        let rows = posts.map { post in
            Self.row(post, threadId: main.id, page: page, onlyPo: onlyPo, forumId: main.forumId)
        }
        write {
            try self.transaction { try self.insertRows(rows, replaceExisting: true) }
        }
    }

    func remove(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        write { try self.deleteThreads(ids) }
    }

    func clear() {
        write { try self.execute("DELETE FROM reading_posts") }
    }

    /// History eviction and deletion also remove searchable text after a restart.
    func retainThreads(_ ids: Set<Int>) {
        write {
            let statement = try self.prepare("SELECT DISTINCT thread_id FROM reading_posts")
            var removed: [Int] = []
            do {
                defer { sqlite3_finalize(statement) }
                var result = sqlite3_step(statement)
                while result == SQLITE_ROW {
                    let id = Int(sqlite3_column_int64(statement, 0))
                    if !ids.contains(id) { removed.append(id) }
                    result = sqlite3_step(statement)
                }
                try self.check(result, expected: SQLITE_DONE)
            }
            try self.deleteThreads(removed)
        }
    }

    static func row(_ post: XDPost, threadId: Int, page: Int, onlyPo: Bool,
                    forumId: Int?, recordedAt: Date = Date()) -> BackupRow {
        let body = XDContent.plainText(post.content)
        let text = post.title.isEmpty || post.title == "无标题" ? body : post.title + "\n" + body
        let searchable = normalized([text, post.name, post.userHash, String(post.id)].joined(separator: "\n"))
        return BackupRow(threadId: threadId, postId: post.id, page: post.id == threadId ? 1 : page,
                         onlyPo: post.id == threadId ? false : onlyPo, body: text, searchable: searchable,
                         recordedAt: recordedAt, userHash: post.userHash, forumId: post.forumId ?? forumId,
                         name: post.name, title: post.title)
    }

    func search(_ query: String, blacklist: BlacklistStore.Payload, browsing: [BrowseRecord],
                filter: Filter = Filter(), threadId: Int? = nil,
                loadedRows: [BackupRow] = []) async throws -> SearchResult {
        let keyword = Self.normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !keyword.isEmpty else { return SearchResult() }
        let history = Dictionary(browsing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cancellation = SearchCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SearchResult, Error>) in
                queue.async {
                    do {
                        if cancellation.isCancelled { throw CancellationError() }
                        try self.connect()
                        // Cancel obsolete queries even when a scan has no matching rows.
                        sqlite3_progress_handler(self.database, 1000, { pointer in
                            guard let pointer else { return 0 }
                            return Unmanaged<SearchCancellation>.fromOpaque(pointer)
                                .takeUnretainedValue().isCancelled ? 1 : 0
                        }, Unmanaged.passUnretained(cancellation).toOpaque())
                        defer { sqlite3_progress_handler(self.database, 0, nil, nil) }
                        let threadFilter = threadId == nil ? "" : " AND p.thread_id = ?"
                        let statement = try self.prepare("""
                            SELECT p.thread_id, p.post_id, p.page, p.only_po, p.body, p.searchable, p.recorded_at,
                                   p.user_hash, p.forum_id, p.name, p.title,
                                   m.thread_id, m.post_id, m.page, m.only_po, m.body, m.searchable, m.recorded_at,
                                   m.user_hash, m.forum_id, m.name, m.title
                            FROM reading_posts p
                            LEFT JOIN reading_posts m ON m.thread_id = p.thread_id AND m.post_id = p.thread_id
                            WHERE instr(p.searchable, ?) > 0\(threadFilter)
                            ORDER BY p.thread_id, p.post_id
                            """)
                        defer { sqlite3_finalize(statement) }
                        try self.bind(keyword, to: statement, at: 1)
                        if let threadId {
                            try self.check(sqlite3_bind_int64(statement, 2, Int64(threadId)))
                        }
                        var found = SearchResult()
                        let loaded = Dictionary(loadedRows.map { ($0.postId, $0) }, uniquingKeysWith: { _, new in new })
                        func collect(_ row: BackupRow, main: BackupRow?) {
                            let id = row.threadId
                            let record = history[id]
                            let threadBlocked = record.map { Self.isBlocked($0, by: blacklist) } ?? false
                            if threadBlocked || main.map({ Self.isBlocked($0, by: blacklist, forumId: record?.forumId) }) == true {
                                found.blockedThreads.insert(id)
                                found.matches.removeValue(forKey: id)
                                return
                            }
                            guard !found.blockedThreads.contains(id),
                                  !Self.isBlocked(row, by: blacklist, forumId: record?.forumId) else { return }
                            guard filter.includes(postId: row.postId, threadId: id,
                                                  forumId: row.forumId ?? main?.forumId ?? record?.forumId) else { return }
                            let hit = Hit(postId: row.postId, page: row.page, onlyPo: row.onlyPo,
                                          excerpt: Self.excerpt(row.body, query: query))
                            found.matches[id, default: Match(hits: [])].hits.append(hit)
                        }
                        var result = sqlite3_step(statement)
                        while result == SQLITE_ROW {
                            if cancellation.isCancelled { throw CancellationError() }
                            let row = Self.readRow(statement)
                            let main = Self.readRow(statement, offset: 11)
                            if loaded[row.postId] == nil {
                                collect(row, main: loaded[row.threadId] ?? (main.postId > 0 ? main : nil))
                            }
                            result = sqlite3_step(statement)
                        }
                        if cancellation.isCancelled { throw CancellationError() }
                        try self.check(result, expected: SQLITE_DONE)
                        for row in loaded.values where row.searchable.contains(keyword) && (threadId == nil || row.threadId == threadId) {
                            if cancellation.isCancelled { throw CancellationError() }
                            collect(row, main: loaded[row.threadId])
                        }
                        for id in Array(found.matches.keys) {
                            found.matches[id]?.hits.sort { $0.postId < $1.postId }
                        }
                        continuation.resume(returning: found)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }

    /// Join the existing history background task so queued page writes can finish.
    func flush(completion: @escaping () -> Void) {
        queue.async { completion() }
    }

    func backup() async throws -> [BackupRow] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.connect()
                    let statement = try self.prepare("SELECT thread_id, post_id, page, only_po, body, searchable, recorded_at, user_hash, forum_id, name, title FROM reading_posts")
                    defer { sqlite3_finalize(statement) }
                    var rows: [BackupRow] = []
                    var result = sqlite3_step(statement)
                    while result == SQLITE_ROW {
                        rows.append(Self.readRow(statement))
                        result = sqlite3_step(statement)
                    }
                    try self.check(result, expected: SQLITE_DONE)
                    continuation.resume(returning: rows)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func restore(_ rows: [BackupRow]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.connect()
                    try self.transaction {
                        try self.execute("DELETE FROM reading_posts")
                        try self.insertRows(rows, replaceExisting: false)
                    }
                    DispatchQueue.main.async { self.revision += 1; self.writeError = nil }
                    continuation.resume(returning: ())
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func isBlocked(_ record: BrowseRecord, by rules: BlacklistStore.Payload) -> Bool {
        if rules.posts[record.id] != nil || rules.users[record.userHash] != nil { return true }
        if let forum = record.forumId, rules.forums.contains(forum) { return true }
        let text = record.preview + record.title
        return rules.keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func isBlocked(_ row: BackupRow, by rules: BlacklistStore.Payload, forumId: Int?) -> Bool {
        if rules.posts[row.threadId] != nil || rules.posts[row.postId] != nil { return true }
        if let forum = row.forumId ?? forumId, rules.forums.contains(forum) { return true }
        if let hash = row.userHash {
            if rules.users[hash] != nil { return true }
        } else {
            // Older indexes stored the author hash immediately before the post ID.
            let fields = row.searchable.components(separatedBy: "\n")
            if fields.count >= 2,
               rules.users.keys.contains(where: { normalized($0) == fields[fields.count - 2] }) { return true }
        }
        guard !rules.keywords.isEmpty else { return false }
        if let title = row.title, let name = row.name {
            let prefix = title + "\n"
            let content = !title.isEmpty && title != "无标题" && row.body.hasPrefix(prefix)
                ? String(row.body.dropFirst(prefix.count)) : row.body
            let text = content + title + name
            return rules.keywords.contains { text.localizedCaseInsensitiveContains($0) }
        }
        // Keep older saved pages searchable without requiring a download.
        // The final two fields are metadata, not keyword-filtered content.
        let text = row.searchable.components(separatedBy: "\n").dropLast(2).joined(separator: "\n")
        return rules.keywords.contains { row.body.localizedCaseInsensitiveContains($0) || text.contains(normalized($0)) }
    }

    private static func readRow(_ statement: OpaquePointer, offset: Int32 = 0) -> BackupRow {
        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, offset + column).map { String(cString: $0) }
        }
        let forum: Int? = sqlite3_column_type(statement, offset + 8) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(statement, offset + 8))
        return BackupRow(threadId: Int(sqlite3_column_int64(statement, offset)),
                         postId: Int(sqlite3_column_int64(statement, offset + 1)),
                         page: Int(sqlite3_column_int64(statement, offset + 2)),
                         onlyPo: sqlite3_column_int(statement, offset + 3) != 0,
                         body: text(4) ?? "", searchable: text(5) ?? "",
                         recordedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, offset + 6)),
                         userHash: text(7), forumId: forum, name: text(9), title: text(10))
    }

    private func bindRow(_ row: BackupRow, to statement: OpaquePointer) throws {
        try check(sqlite3_bind_int64(statement, 1, Int64(row.threadId)))
        try check(sqlite3_bind_int64(statement, 2, Int64(row.postId)))
        try check(sqlite3_bind_int64(statement, 3, Int64(row.page)))
        try check(sqlite3_bind_int(statement, 4, row.onlyPo ? 1 : 0))
        try bind(row.body, to: statement, at: 5)
        try bind(row.searchable, to: statement, at: 6)
        try check(sqlite3_bind_double(statement, 7, row.recordedAt.timeIntervalSince1970))
        try bind(row.userHash, to: statement, at: 8)
        if let forum = row.forumId {
            try check(sqlite3_bind_int64(statement, 9, Int64(forum)))
        } else {
            try check(sqlite3_bind_null(statement, 9))
        }
        try bind(row.name, to: statement, at: 10)
        try bind(row.title, to: statement, at: 11)
    }

    private func insertRows(_ rows: [BackupRow], replaceExisting: Bool) throws {
        let command = replaceExisting ? "INSERT OR REPLACE" : "INSERT"
        let statement = try prepare("""
            \(command) INTO reading_posts
            (thread_id, post_id, page, only_po, body, searchable, recorded_at, user_hash, forum_id, name, title)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        for row in rows {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindRow(row, to: statement)
            try check(sqlite3_step(statement), expected: SQLITE_DONE)
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func excerpt(_ text: String, query: String) -> String {
        let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        let start = match.map { text.index($0.lowerBound, offsetBy: -35, limitedBy: text.startIndex) ?? text.startIndex }
            ?? text.startIndex
        let end = text.index(start, offsetBy: max(160, query.count + 70), limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + String(text[start..<end]) + (end < text.endIndex ? "…" : "")
    }

    private func write(_ operation: @escaping () throws -> Void) {
        queue.async {
            do {
                try self.connect()
                try operation()
                DispatchQueue.main.async { self.revision += 1 }
            } catch {
                DispatchQueue.main.async {
                    self.writeError = "部分阅读内容未能保存到搜索记录，请重新打开相关串后重试。"
                }
            }
        }
    }

    private func connect() throws {
        guard database == nil else { return }
        var connection: OpaquePointer?
        let result = sqlite3_open(path, &connection)
        guard result == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw SearchError.unavailable
        }
        database = connection
        do {
            try check(sqlite3_busy_timeout(connection, 1000))
            try execute("""
                CREATE TABLE IF NOT EXISTS reading_posts (
                    thread_id INTEGER NOT NULL, post_id INTEGER NOT NULL, page INTEGER NOT NULL,
                    only_po INTEGER NOT NULL, body TEXT NOT NULL, searchable TEXT NOT NULL,
                    recorded_at REAL NOT NULL DEFAULT 0,
                    user_hash TEXT, forum_id INTEGER, name TEXT, title TEXT,
                    PRIMARY KEY (thread_id, post_id)
                )
                """)
            let columns = try prepare("PRAGMA table_info(reading_posts)")
            var existingColumns = Set<String>()
            do {
                defer { sqlite3_finalize(columns) }
                var step = sqlite3_step(columns)
                while step == SQLITE_ROW {
                    if let name = sqlite3_column_text(columns, 1) {
                        existingColumns.insert(String(cString: name))
                    }
                    step = sqlite3_step(columns)
                }
                try check(step, expected: SQLITE_DONE)
            }
            let additions = [("recorded_at", "REAL NOT NULL DEFAULT 0"), ("user_hash", "TEXT"),
                             ("forum_id", "INTEGER"), ("name", "TEXT"), ("title", "TEXT")]
            for (name, type) in additions where !existingColumns.contains(name) {
                try execute("ALTER TABLE reading_posts ADD COLUMN \(name) \(type)")
            }
        } catch {
            sqlite3_close(connection)
            database = nil
            throw error
        }
    }

    private func deleteThreads(_ ids: [Int]) throws {
        guard !ids.isEmpty else { return }
        try transaction {
            let statement = try prepare("DELETE FROM reading_posts WHERE thread_id = ?")
            defer { sqlite3_finalize(statement) }
            for id in ids {
                sqlite3_reset(statement)
                try check(sqlite3_bind_int64(statement, 1, Int64(id)))
                try check(sqlite3_step(statement), expected: SQLITE_DONE)
            }
        }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw SearchError.unavailable
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(database, sql, nil, nil, nil))
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        try check(value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) })
    }

    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) throws {
        if let value {
            try bind(value, to: statement, at: index)
        } else {
            try check(sqlite3_bind_null(statement, index))
        }
    }

    private func check(_ result: Int32, expected: Int32 = SQLITE_OK) throws {
        guard result == expected else { throw SearchError.unavailable }
    }

    private enum SearchError: LocalizedError {
        case unavailable
        var errorDescription: String? { "无法读取本地正文搜索记录，请重试。" }
    }

    private final class SearchCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }
}
