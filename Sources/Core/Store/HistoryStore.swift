import Foundation
import SwiftUI
import UIKit

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var browsing: [BrowseRecord] = []
    @Published private(set) var browsingByDay: [(day: Date, records: [BrowseRecord])] = []
    @Published private(set) var posts: [PostRecord] = []
    @Published private(set) var progress: [Int: ReadProgress] = [:]
    @Published private(set) var poProgress: [Int: ReadProgress] = [:]

    typealias ReadProgress = ThreadReadProgress

    @Published private(set) var lastSession: LastReadSession?

    private let sessionStore = JSONStore<[LastReadSession]>(filename: "last_session.json")
    private let browseStore = JSONStore<[BrowseRecord]>(filename: "browsing.json")
    private let postStore = JSONStore<[PostRecord]>(filename: "posts.json")
    private let progressDisk = ProgressDiskStore()
    private let poProgressDisk = ProgressDiskStore(onlyPo: true)
    private var progressAppends = 0

    private let browseLimit = 1000

    private var browsingDirty = false
    private var postsDirty = false
    private var progressDirty = false

    private init() {
        browsing = browseStore.load() ?? []
        posts = postStore.load() ?? []
        progress = progressDisk.load()
        poProgress = poProgressDisk.load()
        lastSession = sessionStore.load()?.first
        regroupBrowsing()
        let reconciled = reconcileReplies([])
        rebuildMyPostIds()
        if !posts.isEmpty, let raw = try? Data(contentsOf: AppPaths.file("posts.json")),
           raw.range(of: Data("\"localId\"".utf8)) == nil {
            postStore.saveNow(posts)
        } else if reconciled {
            postStore.saveNow(posts)
        }
        if progressDisk.loadedJournalLines > 0 {
            progressDisk.compact(progress)
        }
        if poProgressDisk.loadedJournalLines > 0 {
            poProgressDisk.compact(poProgress)
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

    func recordBrowse(_ post: XDPost, page: Int, onlyPo: Bool = false) {
        guard SettingsStore.shared.recordBrowsing else { return }
        let previous = browsing.first(where: { $0.id == post.id })
        let normalProgress = progress[post.id]
        let record = BrowseRecord(id: post.id,
                                  title: post.title,
                                  preview: post.preview,
                                  userHash: post.userHash,
                                  forumId: post.forumId,
                                  replyCount: post.replyCount,
                                  image: post.image,
                                  imageExtension: post.imageExtension,
                                  // Fetching a page does not mean the reader reached it.
                                  lastPage: normalProgress?.page ?? previous?.lastPage ?? (onlyPo ? 1 : page),
                                  lastPostId: normalProgress != nil ? normalProgress?.postId : previous?.lastPostId,
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

    private var myPostIdCache: Set<Int> = []

    func isMyPost(id: Int) -> Bool { myPostIdCache.contains(id) }

    private func rebuildMyPostIds() {
        myPostIdCache = Set(posts.compactMap(\.postId))
    }

    func recordPost(_ record: PostRecord) {
        guard !posts.contains(where: { $0.id == record.id }) else { return }
        let idx = posts.firstIndex(where: { $0.createdAt < record.createdAt }) ?? posts.count
        posts.insert(record, at: idx)
        _ = reconcileReplies([])
        if posts.count > 500 { posts = Array(posts.prefix(500)) }
        rebuildMyPostIds()
        postsDirty = true
        postStore.save(posts)
    }

    func recordObservedReplies(_ replies: [XDPost], mainPostId: Int, forumId: Int?) {
        let cookies = CookieStore.shared
        let observed = replies.compactMap { post -> PostRecord? in
            guard post.id > 0,
                  cookies.isMine(displayId: post.userHash) else { return nil }
            return PostRecord(postId: post.id,
                              status: .accepted,
                              kind: .reply,
                              mainPostId: mainPostId,
                              forumId: post.forumId ?? forumId,
                              title: post.title,
                              content: XDContent.plainText(post.content),
                              userHash: post.userHash,
                              hasImage: post.hasImage,
                              createdAt: post.postTime)
        }
        guard reconcileReplies(observed) else { return }
        posts.sort { $0.createdAt > $1.createdAt }
        if posts.count > 500 { posts = Array(posts.prefix(500)) }
        rebuildMyPostIds()
        postsDirty = true
        postStore.save(posts)
    }

    private func reconcileReplies(_ observed: [PostRecord]) -> Bool {
        ReplyHistoryReconciler.merge(observed, into: &posts) { displayId in
            Set(CookieStore.shared.cookies.filter {
                $0.name == displayId || ($0.displayIds?.contains(displayId) ?? false)
            }.map(\.userHash))
        }
    }

    func removePost(localId: UUID) {
        posts.removeAll { $0.id == localId }
        rebuildMyPostIds()
        postsDirty = true
        postStore.save(posts)
    }

    func clearPosts(kind: PostRecord.Kind? = nil) {
        if let kind {
            posts.removeAll { $0.kind == kind }
        } else {
            posts = []
        }
        rebuildMyPostIds()
        postStore.saveNow(posts)
    }

    func saveProgress(mainPostId: Int, page: Int, postId: Int?, onlyPo: Bool) {
        guard SettingsStore.shared.restoreReadProgress else { return }
        let record = ReadProgress(page: page, postId: postId, updatedAt: Date())
        if onlyPo {
            poProgress[mainPostId] = record
        } else {
            progress[mainPostId] = record
        }
        progressDirty = true
        (onlyPo ? poProgressDisk : progressDisk).append(id: mainPostId, record)
        progressAppends += 1
        if progressAppends >= 2000 {
            progressAppends = 0
            progressDirty = false
            progressDisk.compact(progress)
            poProgressDisk.compact(poProgress)
        }
        if !onlyPo, let idx = browsing.firstIndex(where: { $0.id == mainPostId }) {
            browsing[idx].lastPage = page
            browsing[idx].lastPostId = postId
            browsingDidChange()
        }
    }

    func readProgress(for mainPostId: Int, onlyPo: Bool) -> ReadProgress? {
        guard SettingsStore.shared.restoreReadProgress else { return nil }
        return (onlyPo ? poProgress : progress)[mainPostId]
    }

    func clearProgress() {
        progress = [:]
        poProgress = [:]
        progressAppends = 0
        progressDirty = false
        progressDisk.clear()
        poProgressDisk.clear()
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
            group.enter()
            poProgressDisk.compact(poProgress) { group.leave() }
        }
        group.enter()
        sessionStore.flushAsync(lastSession.map { [$0] } ?? []) { group.leave() }
        group.notify(queue: .main) {
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
        }
    }
}
