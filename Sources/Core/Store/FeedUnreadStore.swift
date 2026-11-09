import Foundation
import Combine

@MainActor
final class FeedUnreadStore: ObservableObject {
    static let shared = FeedUnreadStore()

    struct Entry: Codable {
        var count: Int
        var readCount: Int
        var updatedAt: Date? = nil
    }

    struct Snapshot: Codable {
        var context: String
        var entries: [Int: Entry]
    }

    @Published private(set) var entries: [Int: Entry] = [:]
    private(set) var context = ""
    private var trackedIDs = Set<Int>()
    private var removedDuringRefresh = Set<Int>()
    private var readers: [Int: Set<UUID>] = [:]
    private var legacyCounts: [Int: Int] = [:]
    private let disk = JSONStore<Snapshot>(filename: "feed-unread.json")

    private init() {
        if let saved = disk.load() {
            context = saved.context
            entries = saved.entries
            trackedIDs = Set(entries.keys)
        } else {
            // Capture the pre-upgrade totals before any startup request can replace them.
            let oldCache = JSONStore<[Int: FeedReplyCountStore.Entry]>(filename: "feed-reply-counts.json")
            legacyCounts = (oldCache.load() ?? [:])
                .filter { $0.key > 0 && $0.value.count >= 0 }
                .mapValues { $0.count }
        }
    }

    var hasUnread: Bool { entries.values.contains { $0.count > $0.readCount } }

    func unreadCount(for id: Int) -> Int {
        guard let entry = entries[id] else { return 0 }
        return max(0, entry.count - entry.readCount)
    }

    func configure(context: String) {
        guard self.context != context else { return }
        self.context = context
        // Apply the legacy baseline only to the first feed context after upgrading.
        entries = legacyCounts.mapValues { Entry(count: $0, readCount: $0) }
        legacyCounts = [:]
        trackedIDs = Set(entries.keys)
        persist()
    }

    func beginRefresh() { removedDuringRefresh = [] }

    func track(_ ids: [Int]) {
        trackedIDs.formUnion(ids.filter { !removedDuringRefresh.contains($0) })
    }

    func reconcile(_ ids: Set<Int>) {
        trackedIDs = ids.subtracting(removedDuringRefresh)
        entries = entries.filter { trackedIDs.contains($0.key) }
        persist()
    }

    func remove(_ id: Int) {
        removedDuringRefresh.insert(id)
        trackedIDs.remove(id)
        entries.removeValue(forKey: id)
        persist()
    }

    func observe(_ id: Int, count: Int, context: String) {
        guard self.context == context, trackedIDs.contains(id), count >= 0 else { return }
        var entry = entries[id] ?? Entry(count: count, readCount: count)
        entry.count = count
        entry.updatedAt = Date()
        // Deleted replies must not leave a baseline above the current total.
        entry.readCount = min(entry.readCount, count)
        if !(readers[id]?.isEmpty ?? true) { entry.readCount = count }
        entries[id] = entry
        persist()
    }

    func beginReading(_ id: Int, token: UUID) {
        readers[id, default: []].insert(token)
        markRead(id)
    }

    func endReading(_ id: Int, token: UUID) {
        guard readers[id]?.contains(token) == true else { return }
        markRead(id)
        readers[id]?.remove(token)
        if readers[id]?.isEmpty == true { readers.removeValue(forKey: id) }
    }

    private func markRead(_ id: Int) {
        guard var entry = entries[id], entry.readCount != entry.count else { return }
        entry.readCount = entry.count
        entry.updatedAt = Date()
        entries[id] = entry
        persist()
    }

    func markRead(_ ids: Set<Int>) {
        let now = Date()
        for id in ids {
            guard var entry = entries[id], entry.readCount != entry.count else { continue }
            entry.readCount = entry.count
            entry.updatedAt = now
            entries[id] = entry
        }
        persist()
    }

    private func persist() {
        disk.save(snapshot)
    }

    func flush() {
        disk.saveNow(snapshot)
    }

    var snapshot: Snapshot { Snapshot(context: context, entries: entries) }

    func restore(_ snapshot: Snapshot) throws {
        guard disk.saveNowChecked(snapshot) else { throw CocoaError(.fileWriteUnknown) }
        context = snapshot.context
        entries = snapshot.entries
        trackedIDs = Set(entries.keys)
        legacyCounts = [:]
        readers = [:]
        removedDuringRefresh = []
    }
}
