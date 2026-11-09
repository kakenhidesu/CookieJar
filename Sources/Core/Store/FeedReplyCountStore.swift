import Foundation
import Combine

@MainActor
final class FeedReplyCountStore: ObservableObject {
    struct Entry: Codable, Equatable {
        var count: Int
        var updatedAt: Date
    }

    typealias Fetch = @MainActor (Int, String?) async throws -> Int

    static let shared: FeedReplyCountStore = {
        let disk = JSONStore<[Int: Entry]>(filename: "feed-reply-counts.json")
        return FeedReplyCountStore(cached: disk.load() ?? [:], fetch: { id, cookie in
            try await XDAPI.shared.replyCount(mainPostId: id, cookie: cookie)
        }, persist: { disk.save($0) })
    }()

    @Published private(set) var entries: [Int: Entry]
    @Published private(set) var loadingIDs: Set<Int> = []
    @Published private(set) var failedIDs: Set<Int> = []

    private struct Request {
        var id: Int
        var cookie: String?
        var context: String
    }

    private let fetch: Fetch
    private let persist: ([Int: Entry]) -> Void
    private let now: () -> Date
    private let lifetime: TimeInterval
    private let concurrencyLimit: Int
    private var pending: [Request] = []
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var context = ""
    private var generation = UUID()

    init(cached: [Int: Entry] = [:], concurrencyLimit: Int = 3,
         lifetime: TimeInterval = 300, now: @escaping () -> Date = Date.init,
         fetch: @escaping Fetch, persist: @escaping ([Int: Entry]) -> Void = { _ in }) {
        entries = cached.filter { $0.key > 0 && $0.value.count >= 0 }
        self.concurrencyLimit = max(1, concurrencyLimit)
        self.lifetime = lifetime
        self.now = now
        self.fetch = fetch
        self.persist = persist
    }

    func request(_ ids: [Int], cookie: String?, force: Bool = false) {
        let selectedContext = SettingsStore.shared.feedContextID
        if context != selectedContext {
            cancelPending()
            context = selectedContext
        }
        let date = now()
        for id in ids where id > 0 {
            // Includes queued requests, so refreshes and duplicate cards share one fetch.
            guard !loadingIDs.contains(id) else { continue }
            if !force, let entry = entries[id] {
                let age = date.timeIntervalSince(entry.updatedAt)
                if age >= 0 && age < lifetime { continue }
            }
            failedIDs.remove(id)
            loadingIDs.insert(id)
            pending.append(Request(id: id, cookie: cookie, context: SettingsStore.shared.feedContextID))
        }
        startNext()
    }

    private func startNext() {
        while tasks.count < concurrencyLimit, !pending.isEmpty {
            let request = pending.removeFirst()
            let startedAt = now()
            let generation = self.generation
            tasks[request.id] = Task { @MainActor in
                do {
                    let count = try await fetch(request.id, request.cookie)
                    guard generation == self.generation, !Task.isCancelled else { return }
                    guard count >= 0 else { throw XDError.decode("回复数无效") }
                    // A thread opened after this request started may have a newer total.
                    if entries[request.id].map({ $0.updatedAt <= startedAt }) ?? true {
                        entries[request.id] = Entry(count: count, updatedAt: now())
                    }
                    if let latest = entries[request.id] {
                        FeedUnreadStore.shared.observe(request.id, count: latest.count, context: request.context)
                    }
                    // Keep only recent totals; no post content or credentials are persisted.
                    if entries.count > 1000 {
                        let recent = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(1000)
                        entries = Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
                    }
                    failedIDs.remove(request.id)
                    persist(entries)
                } catch {
                    guard generation == self.generation, !Task.isCancelled else { return }
                    // Preserve a previous total on failure, including a genuine zero.
                    failedIDs.insert(request.id)
                }
                loadingIDs.remove(request.id)
                tasks.removeValue(forKey: request.id)
                startNext()
            }
        }
    }

    func recordReadCount(_ id: Int, count: Int) {
        guard count >= 0 else { return }
        entries[id] = Entry(count: count, updatedAt: now())
        FeedUnreadStore.shared.observe(id, count: count, context: SettingsStore.shared.feedContextID)
        persist(entries)
    }

    func waitUntilFinished() async {
        while let task = tasks.values.first { await task.value }
    }

    func cancelPending() {
        generation = UUID()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        pending = []
        loadingIDs = []
        failedIDs = []
    }
}
