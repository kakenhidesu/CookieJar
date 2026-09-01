import Foundation
import SwiftUI

struct BrowseRecord: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var preview: String
    var userHash: String
    var forumId: Int?
    var replyCount: Int?
    var image: String
    var imageExtension: String
    var lastPage: Int
    var lastPostId: Int?
    var browsedAt: Date
}

struct PostRecord: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case thread, reply }
    var id: Int
    var kind: Kind
    var mainPostId: Int?
    var forumId: Int?
    var title: String
    var content: String
    var userHash: String
    var hasImage: Bool
    var createdAt: Date
}

struct LastReadSession: Codable, Hashable {
    var mainPostId: Int
    var page: Int
    var postId: Int?
    var onlyPo: Bool
    var savedAt: Date
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var browsing: [BrowseRecord] = []
    @Published private(set) var browsingByDay: [(day: Date, records: [BrowseRecord])] = []
    @Published private(set) var posts: [PostRecord] = []
    @Published private(set) var progress: [Int: ReadProgress] = [:]

    struct ReadProgress: Codable, Hashable {
        var page: Int
        var postId: Int?
        var updatedAt: Date
    }

    @Published private(set) var lastSession: LastReadSession?

    private let sessionStore = JSONStore<[LastReadSession]>(filename: "last_session.json")
    private let browseStore = JSONStore<[BrowseRecord]>(filename: "browsing.json")
    private let postStore = JSONStore<[PostRecord]>(filename: "posts.json")
    private let progressDisk = ProgressDiskStore()
    private var progressAppends = 0

    private let browseLimit = 1000

    private var browsingDirty = false
    private var postsDirty = false
    private var progressDirty = false

    private init() {
        browsing = browseStore.load() ?? []
        posts = postStore.load() ?? []
        progress = progressDisk.load()
        lastSession = sessionStore.load()?.first
        regroupBrowsing()
        rebuildMyPostIds()
        if progressDisk.loadedJournalLines > 0 {
            progressDisk.compact(progress)
        }
    }

    func noteReading(mainPostId: Int, page: Int, postId: Int?, onlyPo: Bool) {
        if let old = lastSession, old.mainPostId == mainPostId, old.page == page,
           old.postId == postId, old.onlyPo == onlyPo {
            return
        }
        let session = LastReadSession(mainPostId: mainPostId, page: page,
                                      postId: postId, onlyPo: onlyPo, savedAt: Date())
        lastSession = session
        sessionStore.save([session])
    }

    func clearReading() {
        guard let old = lastSession else { return }
        lastSession = nil
        sessionStore.saveNow([])
        LaunchLog.mark("离开串 No.\(old.mainPostId)，清除恢复点")
    }

    private func browsingDidChange() {
        regroupBrowsing()
        browsingDirty = true
        browseStore.save(browsing)
    }

    private func regroupBrowsing() {
        let cal = Calendar.current
        browsingByDay = Dictionary(grouping: browsing) { cal.startOfDay(for: $0.browsedAt) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, records: $0.value) }
    }

    func recordBrowse(_ post: XDPost, page: Int) {
        guard SettingsStore.shared.recordBrowsing else { return }
        let record = BrowseRecord(id: post.id,
                                  title: post.title,
                                  preview: post.preview,
                                  userHash: post.userHash,
                                  forumId: post.forumId,
                                  replyCount: post.replyCount,
                                  image: post.image,
                                  imageExtension: post.imageExtension,
                                  lastPage: page,
                                  lastPostId: progress[post.id]?.postId,
                                  browsedAt: Date())
        browsing.removeAll { $0.id == post.id }
        browsing.insert(record, at: 0)
        if browsing.count > browseLimit { browsing = Array(browsing.prefix(browseLimit)) }
        browsingDidChange()
    }

    func removeBrowse(id: Int) {
        browsing.removeAll { $0.id == id }
        browsingDidChange()
    }

    func clearBrowsing() {
        browsing = []
        regroupBrowsing()
        browseStore.saveNow(browsing)
    }

    var myPostIds: Set<Int> { Set(posts.map(\.id).filter { $0 > 0 }) }

    func isMyPost(id: Int) -> Bool { myPostIdCache.contains(id) }
    private var myPostIdCache: Set<Int> = []

    private func rebuildMyPostIds() {
        myPostIdCache = myPostIds
    }

    func recordPost(_ record: PostRecord) {
        posts.insert(record, at: 0)
        rebuildMyPostIds()
        if posts.count > 500 { posts = Array(posts.prefix(500)) }
        postsDirty = true
        postStore.save(posts)
    }

    func fillLastPostId(_ id: Int, for createdAt: Date) {
        guard let idx = posts.firstIndex(where: { $0.createdAt == createdAt }) else { return }
        posts[idx].id = id
        if posts[idx].kind == .thread { posts[idx].mainPostId = id }
        rebuildMyPostIds()
        postsDirty = true
        postStore.save(posts)
    }

    func removePost(id: Int) {
        posts.removeAll { $0.id == id }
        rebuildMyPostIds()
        postsDirty = true
        postStore.save(posts)
    }

    func clearPosts() {
        posts = []
        rebuildMyPostIds()
        postStore.saveNow(posts)
    }

    func saveProgress(mainPostId: Int, page: Int, postId: Int?) {
        guard SettingsStore.shared.restoreReadProgress else { return }
        let record = ReadProgress(page: page, postId: postId, updatedAt: Date())
        progress[mainPostId] = record
        progressDirty = true
        progressDisk.append(id: mainPostId, record)
        progressAppends += 1
        if progressAppends >= 2000 {
            progressAppends = 0
            progressDirty = false
            progressDisk.compact(progress)
        }
        if let idx = browsing.firstIndex(where: { $0.id == mainPostId }) {
            browsing[idx].lastPage = page
            browsing[idx].lastPostId = postId
            browsingDidChange()
        }
    }

    func readProgress(for mainPostId: Int) -> ReadProgress? {
        SettingsStore.shared.restoreReadProgress ? progress[mainPostId] : nil
    }

    func clearProgress() {
        progress = [:]
        progressAppends = 0
        progressDirty = false
        progressDisk.clear()
    }

    func flush() {
        if browsingDirty { browseStore.saveNow(browsing); browsingDirty = false }
        if postsDirty { postStore.saveNow(posts); postsDirty = false }
        if progressDirty {
            progressAppends = 0
            progressDirty = false
            progressDisk.compact(progress)
        }
        sessionStore.saveNow(lastSession.map { [$0] } ?? [])
    }
}
