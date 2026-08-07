import Foundation
import SwiftUI

final class ForumStore: ObservableObject {
    static let shared = ForumStore()

    struct Cache: Codable {
        var groups: [ForumGroup]
        var forums: [Forum]
        var timelines: [Timeline]
        var updatedAt: Date
    }

    @Published private(set) var groups: [ForumGroup] = []
    @Published private(set) var forums: [Forum] = []
    @Published private(set) var timelines: [Timeline] = []
    @Published private(set) var isLoading = false

    private var forumsById: [Int: Forum] = [:]
    private var timelinesById: [Int: Timeline] = [:]

    @AppStorage("forum.order") private var orderRaw: String = ""
    @AppStorage("forum.hidden") private var hiddenRaw: String = ""

    private let store = JSONStore<Cache>(filename: "forums.json")

    private init() {
        if let cache = store.load() {
            apply(groups: cache.groups, forums: cache.forums, timelines: cache.timelines)
        }
    }

    private func apply(groups: [ForumGroup], forums: [Forum], timelines: [Timeline]) {
        self.groups = groups
        self.forums = forums
        self.timelines = timelines
        forumsById = Dictionary(forums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        timelinesById = Dictionary(timelines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var order: [Int] {
        get { orderRaw.split(separator: ",").compactMap { Int($0) } }
        set { orderRaw = newValue.map(String.init).joined(separator: ",") }
    }

    var hidden: Set<Int> {
        get { Set(hiddenRaw.split(separator: ",").compactMap { Int($0) }) }
        set { hiddenRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    func isHidden(_ id: Int) -> Bool { hidden.contains(id) }

    func toggleHidden(_ id: Int) {
        var h = hidden
        if h.contains(id) { h.remove(id) } else { h.insert(id) }
        hidden = h
        objectWillChange.send()
    }

    func orderedForums(includeHidden: Bool = false) -> [Forum] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let hiddenSet = hidden
        return forums
            .filter { includeHidden || !hiddenSet.contains($0.id) }
            .sorted { a, b in
                let ra = rank[a.id] ?? (10_000 + a.sort)
                let rb = rank[b.id] ?? (10_000 + b.sort)
                if ra != rb { return ra < rb }
                return a.sort < b.sort
            }
    }

    var visibleForums: [Forum] { orderedForums() }

    var visibleTimelines: [Timeline] { timelines }

    func forum(id: Int) -> Forum? { forumsById[id] }
    func timeline(id: Int) -> Timeline? { timelinesById[id] }

    func name(forId id: Int, isTimeline: Bool = false) -> String {
        if isTimeline { return timeline(id: id)?.showName ?? "时间线" }
        if id < 0 { return timeline(id: id)?.showName ?? "时间线" }
        return forum(id: id)?.showName ?? "版块 \(id)"
    }

    func grouped() -> [(ForumGroup, [Forum])] {
        let visible = visibleForums
        return groups
            .sorted { $0.sort < $1.sort }
            .map { g in (g, visible.filter { $0.groupId == g.id }) }
            .filter { !$0.1.isEmpty }
    }

    @MainActor
    func refresh() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let cookie = CookieStore.shared.cookieValue
            async let listTask = XDAPI.shared.forumList(cookie: cookie)
            async let timelineTask = XDAPI.shared.timelineList(cookie: cookie)
            let list = try await listTask
            let tl = (try? await timelineTask) ?? list.timelines

            apply(groups: list.groups,
                  forums: list.forums,
                  timelines: tl.isEmpty ? list.timelines : tl)
            store.save(Cache(groups: groups, forums: forums, timelines: timelines, updatedAt: Date()))
        } catch {
            Toast.shared.error(error)
        }
    }
}
