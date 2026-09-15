import Foundation
import SwiftUI
import UIKit

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
    enum SendStatus: String, Codable { case accepted, resultUnknown, legacy }

    var id: UUID
    var postId: Int?
    var status: SendStatus
    var kind: Kind
    var mainPostId: Int?
    var forumId: Int?
    var title: String
    var content: String
    var userHash: String
    var hasImage: Bool
    var createdAt: Date

    init(id: UUID = UUID(), postId: Int? = nil, status: SendStatus, kind: Kind,
         mainPostId: Int?, forumId: Int?, title: String, content: String,
         userHash: String, hasImage: Bool, createdAt: Date) {
        self.id = id
        self.postId = postId
        self.status = status
        self.kind = kind
        self.mainPostId = mainPostId
        self.forumId = forumId
        self.title = title
        self.content = content
        self.userHash = userHash
        self.hasImage = hasImage
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id = "localId", postId, status, kind, mainPostId, forumId, title, content, userHash, hasImage, createdAt
    }

    private enum LegacyKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        mainPostId = try c.decodeIfPresent(Int.self, forKey: .mainPostId)
        forumId = try c.decodeIfPresent(Int.self, forKey: .forumId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        userHash = try c.decodeIfPresent(String.self, forKey: .userHash) ?? ""
        hasImage = try c.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if let localId = try c.decodeIfPresent(UUID.self, forKey: .id) {
            id = localId
            postId = try c.decodeIfPresent(Int.self, forKey: .postId)
            status = (try? c.decodeIfPresent(SendStatus.self, forKey: .status)) ?? .legacy
        } else {
            let legacyId = (try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Int.self, forKey: .id)) ?? 0
            id = UUID()
            postId = legacyId > 0 ? legacyId : nil
            status = .legacy
        }
    }
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
        if !posts.isEmpty, let raw = try? Data(contentsOf: AppPaths.file("posts.json")),
           raw.range(of: Data("\"localId\"".utf8)) == nil {
            postStore.saveNow(posts)
        }
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

    func recordPost(_ record: PostRecord) {
        guard !posts.contains(where: { $0.id == record.id }) else { return }
        let idx = posts.firstIndex(where: { $0.createdAt < record.createdAt }) ?? posts.count
        posts.insert(record, at: idx)
        if posts.count > 500 { posts = Array(posts.prefix(500)) }
        postsDirty = true
        postStore.save(posts)
    }

    func removePost(localId: UUID) {
        posts.removeAll { $0.id == localId }
        postsDirty = true
        postStore.save(posts)
    }

    func clearPosts(kind: PostRecord.Kind? = nil) {
        if let kind {
            posts.removeAll { $0.kind == kind }
        } else {
            posts = []
        }
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
        let bg = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        let group = DispatchGroup()
        if browsingDirty {
            browsingDirty = false
            group.enter()
            browseStore.flushAsync(browsing) { group.leave() }
        }
        if postsDirty {
            postsDirty = false
            group.enter()
            postStore.flushAsync(posts) { group.leave() }
        }
        if progressDirty {
            progressAppends = 0
            progressDirty = false
            group.enter()
            progressDisk.compact(progress) { group.leave() }
        }
        group.enter()
        sessionStore.flushAsync(lastSession.map { [$0] } ?? []) { group.leave() }
        group.notify(queue: .main) {
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
        }
    }
}
