import Foundation

final class ProgressDiskStore {
    struct Snapshot: Codable {
        var version: Int
        var entries: [Int: ThreadReadProgress]
    }

    private struct JournalLine: Codable {
        var id: Int
        var page: Int
        var postId: Int?
        var at: Date
    }

    private let snapshotURL: URL
    private let backupURL: URL
    private let journalURL: URL
    private let queue = DispatchQueue(label: "xd.progress", qos: .utility)
    private(set) var loadedJournalLines = 0

    init(onlyPo: Bool = false, directory: URL = AppPaths.dataDirectory) {
        // Keep the old filenames and schema for normal reading; no destructive migration is needed.
        let name = onlyPo ? "progress-po" : "progress"
        snapshotURL = directory.appendingPathComponent("\(name).json")
        backupURL = directory.appendingPathComponent("\(name).json.bak")
        journalURL = directory.appendingPathComponent("\(name)-journal.jsonl")
    }

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

    func load() -> [Int: ThreadReadProgress] {
        let decoder = Self.makeDecoder()
        func readSnapshot(_ url: URL) -> [Int: ThreadReadProgress]? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let snap = try? decoder.decode(Snapshot.self, from: data), snap.version == 1 {
                return snap.entries
            }
            return try? decoder.decode([Int: ThreadReadProgress].self, from: data)
        }
        var entries = readSnapshot(snapshotURL) ?? readSnapshot(backupURL) ?? [:]
        loadedJournalLines = 0
        if let data = try? Data(contentsOf: journalURL), !data.isEmpty {
            for chunk in data.split(separator: UInt8(ascii: "\n")) {
                guard let line = try? decoder.decode(JournalLine.self, from: Data(chunk)) else { continue }
                // Preserve legacy journal order, including entries saved after a device clock change.
                entries[line.id] = ThreadReadProgress(page: line.page, postId: line.postId, updatedAt: line.at)
                loadedJournalLines += 1
            }
        }
        return entries
    }

    func append(id: Int, _ record: ThreadReadProgress) {
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

    func compact(_ entries: [Int: ThreadReadProgress], completion: (() -> Void)? = nil) {
        queue.async {
            defer { completion?() }
            guard let data = try? Self.makeEncoder().encode(Snapshot(version: 1, entries: entries)) else { return }
            guard (try? data.write(to: self.snapshotURL, options: .atomic)) != nil else { return }
            try? data.write(to: self.backupURL, options: .atomic)
            try? Data().write(to: self.journalURL, options: .atomic)
        }
    }

    func clear() {
        compact([:])
    }
}
