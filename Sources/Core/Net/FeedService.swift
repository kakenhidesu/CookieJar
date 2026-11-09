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

    func clear() {
        ids = []
        store.saveNow([])
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
        let context = settings.feedContextID
        let result: [XDPost]
        if settings.useHTMLFeed {
            result = try await XDAPI.shared.htmlFeed(page: page, cookie: try requireCookie())
        } else {
            result = try await XDAPI.shared.feed(uuid: settings.feedUUID,
                                                 page: page,
                                                 cookie: CookieStore.shared.cookieValue)
        }
        try Task.checkCancellation()
        await MainActor.run {
            guard !Task.isCancelled, settings.feedContextID == context,
                  !FeedViewModel.shared.isRestoring else { return }
            SubscriptionCache.shared.merge(result.map(\.id))
        }
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

    @MainActor
    func unsubscribe(mainPostId: Int, expectedContext: String? = nil) async throws {
        let context = settings.feedContextID
        let cookie = try requireCookie()
        let useHTML = settings.useHTMLFeed
        let uuid = settings.feedUUID
        let generation = HistoryStore.shared.restoreGeneration
        if let expectedContext, expectedContext != context { throw CancellationError() }
        if useHTML {
            try await XDAPI.shared.deleteHTMLFeed(mainPostId: mainPostId, cookie: cookie)
        } else {
            try await XDAPI.shared.deleteFeed(uuid: uuid,
                                              mainPostId: mainPostId,
                                              cookie: cookie)
        }
        guard settings.feedContextID == context,
              HistoryStore.shared.restoreGeneration == generation,
              !FeedViewModel.shared.isRestoring else { return }
        SubscriptionCache.shared.remove(mainPostId)
        FeedUnreadStore.shared.remove(mainPostId)
        FeedLibraryStore.shared.removeThread(mainPostId)
    }
}
