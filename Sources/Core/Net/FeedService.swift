import Foundation

final class SubscriptionCache: ObservableObject {
    static let shared = SubscriptionCache()

    @Published private(set) var ids: Set<Int> = []
    private let store = JSONStore<[Int]>(filename: "subscriptions.json")

    private init() {
        ids = Set(store.load() ?? [])
    }

    func contains(_ id: Int) -> Bool { ids.contains(id) }

    func insert(_ id: Int) {
        guard !ids.contains(id) else { return }
        ids.insert(id)
        persist()
    }

    func remove(_ id: Int) {
        guard ids.contains(id) else { return }
        ids.remove(id)
        persist()
    }

    func merge(_ newIds: [Int]) {
        let before = ids.count
        ids.formUnion(newIds)
        if ids.count != before { persist() }
    }

    private func persist() {
        store.save(Array(ids))
    }
}

struct FeedService {
    static let shared = FeedService()

    private var settings: SettingsStore { SettingsStore.shared }

    private func requireCookie() throws -> String {
        guard let cookie = CookieStore.shared.cookieValue else { throw XDError.needCookie }
        return cookie
    }

    func feed(page: Int) async throws -> [XDPost] {
        let result: [XDPost]
        if settings.useHTMLFeed {
            result = try await XDAPI.shared.htmlFeed(page: page, cookie: try requireCookie())
        } else {
            result = try await XDAPI.shared.feed(uuid: settings.feedUUID,
                                                 page: page,
                                                 cookie: CookieStore.shared.cookieValue)
        }
        await MainActor.run { SubscriptionCache.shared.merge(result.map(\.id)) }
        return result
    }

    func subscribe(mainPostId: Int) async throws {
        if settings.useHTMLFeed {
            try await XDAPI.shared.addHTMLFeed(mainPostId: mainPostId, cookie: try requireCookie())
        } else {
            try await XDAPI.shared.addFeed(uuid: settings.feedUUID,
                                           mainPostId: mainPostId,
                                           cookie: try requireCookie())
        }
        await MainActor.run { SubscriptionCache.shared.insert(mainPostId) }
    }

    func unsubscribe(mainPostId: Int) async throws {
        if settings.useHTMLFeed {
            try await XDAPI.shared.deleteHTMLFeed(mainPostId: mainPostId, cookie: try requireCookie())
        } else {
            try await XDAPI.shared.deleteFeed(uuid: settings.feedUUID,
                                              mainPostId: mainPostId,
                                              cookie: try requireCookie())
        }
        await MainActor.run { SubscriptionCache.shared.remove(mainPostId) }
    }
}
