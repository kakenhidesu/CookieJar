import Foundation

final class ProgressDiskStore {
    struct Snapshot: Codable {
        var version: Int
        var entries: [Int: HistoryStore.ReadProgress]
    }

    private struct JournalLine: Codable {
        var id: Int
        var page: Int
        var postId: Int?
        var at: Date
    }

    private let snapshotURL = AppPaths.file("progress.json")
    private let backupURL = AppPaths.file("progress.json.bak")
    private let journalURL = AppPaths.file("progress-journal.jsonl")
    private let queue = DispatchQueue(label: "xd.progress", qos: .utility)
    private(set) var loadedJournalLines = 0

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    func load() -> [Int: HistoryStore.ReadProgress] {
        var entries: [Int: HistoryStore.ReadProgress] = [:]
        let decoder = Self.makeDecoder()
        if let data = try? Data(contentsOf: snapshotURL) {
            if let snap = try? decoder.decode(Snapshot.self, from: data) {
                entries = snap.entries
            } else if let legacy = try? decoder.decode([Int: HistoryStore.ReadProgress].self, from: data) {
                entries = legacy
                try? FileManager.default.copyItem(at: snapshotURL, to: backupURL)
            }
        }
        if let data = try? Data(contentsOf: journalURL), !data.isEmpty {
            for chunk in data.split(separator: UInt8(ascii: "\n")) {
                guard let line = try? decoder.decode(JournalLine.self, from: Data(chunk)) else { continue }
                entries[line.id] = HistoryStore.ReadProgress(page: line.page, postId: line.postId, updatedAt: line.at)
                loadedJournalLines += 1
            }
        }
        return entries
    }

    func append(id: Int, _ record: HistoryStore.ReadProgress) {
        queue.async {
            let line = JournalLine(id: id, page: record.page, postId: record.postId, at: record.updatedAt)
            guard var data = try? Self.makeEncoder().encode(line) else { return }
            data.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: self.journalURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: self.journalURL, options: .atomic)
            }
        }
    }

    func compact(_ entries: [Int: HistoryStore.ReadProgress]) {
        queue.async {
            guard let data = try? Self.makeEncoder().encode(Snapshot(version: 1, entries: entries)) else { return }
            try? data.write(to: self.snapshotURL, options: .atomic)
            try? Data().write(to: self.journalURL, options: .atomic)
        }
    }

    func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: self.journalURL)
            if let data = try? Self.makeEncoder().encode(Snapshot(version: 1, entries: [:])) {
                try? data.write(to: self.snapshotURL, options: .atomic)
            }
        }
    }
}
