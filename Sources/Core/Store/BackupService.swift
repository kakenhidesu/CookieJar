import Foundation
import UIKit

enum BackupError: LocalizedError {
    case invalidFile, unsupportedVersion, restoreFailed, rollbackFailed
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "无法读取这个备份文件。"
        case .unsupportedVersion: return "此备份版本暂不支持。"
        case .restoreFailed: return "导入失败，已恢复原有数据。"
        case .rollbackFailed: return "导入未完成，请重新导入备份。"
        }
    }
}

struct BackupArchive: Codable {
    var format = "CookieJarBackup"
    var version = 1
    var createdAt = Date()
    var history: HistoryStore.Backup
    var drafts: DraftStore.Backup
    var blacklist: BlacklistStore.Payload
    var settings: [String: BackupSetting]
    var library: FeedLibraryStore.Snapshot
    var unread: FeedUnreadStore.Snapshot
    var emoticons: EmoticonStore.Backup
    var search: [ReadingSearchStore.BackupRow]

    func validate() throws {
        guard format == "CookieJarBackup" else { throw BackupError.invalidFile }
        guard version == 1 else { throw BackupError.unsupportedVersion }
        try BackupSettings.validate(settings)
        if case .string(let uuid) = settings["set.feedUUID"], case .bool(let html) = settings["set.useHTMLFeed"] {
            let context = html ? "html" : "uuid:\(uuid)"
            guard unread.context == context || (unread.context.isEmpty && unread.entries.isEmpty) else {
                throw BackupError.invalidFile
            }
        }
        guard Set(history.browsing.map(\.id)).count == history.browsing.count,
              Set(history.posts.map(\.id)).count == history.posts.count,
              Set(drafts.drafts.map(\.id)).count == drafts.drafts.count,
              history.browsing.allSatisfy({ $0.id > 0 && $0.lastPage > 0 }),
              history.progress.allSatisfy({ $0.key > 0 && $0.value.page > 0 }),
              history.poProgress.allSatisfy({ $0.key > 0 && $0.value.page > 0 }),
              unread.entries.allSatisfy({ $0.key > 0 && $0.value.readCount >= 0 && $0.value.count >= $0.value.readCount })
        else { throw BackupError.invalidFile }
        let threadIDs = Set(history.browsing.map(\.id))
        var postKeys = Set<String>()
        for row in search {
            guard threadIDs.contains(row.threadId), row.postId > 0, row.page > 0,
                  postKeys.insert("\(row.threadId):\(row.postId)").inserted else { throw BackupError.invalidFile }
        }
        for draft in drafts.drafts {
            if let name = draft.imageFile {
                guard DraftStore.validImageName(name, for: draft.id), drafts.images[name] != nil else {
                    throw BackupError.invalidFile
                }
            }
        }
        for collection in library.values {
            let groups = Set(collection.groups.map(\.id))
            guard groups.count == collection.groups.count,
                  collection.assignments.allSatisfy({ $0.key > 0 && groups.contains($0.value) }),
                  collection.pinned.allSatisfy({ $0 > 0 }) else { throw BackupError.invalidFile }
        }
    }

    func merging(into current: BackupArchive) -> BackupArchive {
        var merged = self
        merged.history.browsing = Self.merge(current.history.browsing, history.browsing, key: \.id) {
            $0.browsedAt > $1.browsedAt ? $0 : $1
        }.sorted { $0.browsedAt > $1.browsedAt }
        merged.history.browsing = Array(merged.history.browsing.prefix(1000))
        merged.history.posts = Self.mergePosts(current.history.posts, history.posts)
        merged.history.progress = current.history.progress.merging(history.progress) { $0.updatedAt > $1.updatedAt ? $0 : $1 }
        merged.history.poProgress = current.history.poProgress.merging(history.poProgress) { $0.updatedAt > $1.updatedAt ? $0 : $1 }
        if let local = current.history.lastSession, local.savedAt > (history.lastSession?.savedAt ?? .distantPast) {
            merged.history.lastSession = local
        }
        merged.drafts = Self.mergeDrafts(current.drafts, drafts)
        merged.blacklist.users = current.blacklist.users.merging(blacklist.users) { _, new in new }
        merged.blacklist.posts = current.blacklist.posts.merging(blacklist.posts) { _, new in new }
        merged.blacklist.forums.formUnion(current.blacklist.forums)
        merged.blacklist.keywords = Array(Set(current.blacklist.keywords + blacklist.keywords)).sorted()
        merged.library = current.library.merging(library) { local, incoming in
            var value = incoming
            value.groups = Self.merge(local.groups, incoming.groups, key: \.id) { _, new in new }.sorted { $0.name < $1.name }
            value.pinned.formUnion(local.pinned)
            value.assignments = local.assignments.merging(incoming.assignments) { _, new in new }
            return value
        }
        if current.unread.context == unread.context {
            merged.unread.entries = current.unread.entries.merging(unread.entries) { local, incoming in
                (local.updatedAt ?? .distantPast) >= (incoming.updatedAt ?? .distantPast) ? local : incoming
            }
        }
        merged.emoticons.custom = Self.merge(current.emoticons.custom, emoticons.custom, key: \.id) { _, new in new }
            .sorted { $0.name < $1.name }
        merged.emoticons.lastUsed = current.emoticons.lastUsed.merging(emoticons.lastUsed) { max($0, $1) }
        var favoriteIDs = Set<String>()
        merged.emoticons.favoriteIDs = (current.emoticons.favoriteIDs + emoticons.favoriteIDs)
            .filter { favoriteIDs.insert($0).inserted }
        let threads = Set(merged.history.browsing.map(\.id))
        let indexed = Dictionary((current.search + search).map { ("\($0.threadId):\($0.postId)", $0) }, uniquingKeysWith: {
            $0.recordedAt > $1.recordedAt ? $0 : $1
        })
        merged.search = indexed.values.filter { threads.contains($0.threadId) }
        return merged
    }

    private static func mergePosts(_ local: [PostRecord], _ incoming: [PostRecord]) -> [PostRecord] {
        let posts = local + incoming
        // Map older versions of the same local record to its confirmed post ID.
        let confirmed = Dictionary(posts.filter { confirmedPostID($0) != nil }.map { ($0.id, $0) },
                                   uniquingKeysWith: { $0.createdAt > $1.createdAt ? $0 : $1 })
        let merged = Dictionary(posts.map { record in
            let postID = confirmed[record.id].flatMap(confirmedPostID)
            let key = postID.map { "post:\($0)" } ?? "local:\(record.id)"
            return (key, record)
        }, uniquingKeysWith: { first, second in
            let firstConfirmed = confirmedPostID(first) != nil
            let secondConfirmed = confirmedPostID(second) != nil
            if firstConfirmed != secondConfirmed { return firstConfirmed ? first : second }
            return first.createdAt > second.createdAt ? first : second
        })
        return Array(merged.values.sorted { $0.createdAt > $1.createdAt }.prefix(500))
    }

    private static func mergeDrafts(_ local: DraftStore.Backup, _ incoming: DraftStore.Backup) -> DraftStore.Backup {
        let drafts = Array(merge(local.drafts, incoming.drafts, key: \.id) {
            $0.updatedAt >= $1.updatedAt ? $0 : $1
        }.sorted { $0.updatedAt > $1.updatedAt }.prefix(200))
        let localDrafts = Dictionary(local.drafts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var images: [String: Data] = [:]
        for draft in drafts {
            guard let name = draft.imageFile else { continue }
            let useLocal = localDrafts[draft.id].map { $0.updatedAt == draft.updatedAt && $0.imageFile == name } ?? false
            images[name] = useLocal ? local.images[name] : incoming.images[name]
        }
        return DraftStore.Backup(drafts: drafts, images: images)
    }

    private static func confirmedPostID(_ record: PostRecord) -> Int? {
        guard record.status == .accepted, let id = record.postId, id > 0 else { return nil }
        return id
    }

    private static func merge<T, Key: Hashable>(_ local: [T], _ incoming: [T], key: KeyPath<T, Key>,
                                               choose: (T, T) -> T) -> [T] {
        Array(Dictionary((local + incoming).map { ($0[keyPath: key], $0) }, uniquingKeysWith: choose).values)
    }
}

@MainActor
enum BackupService {
    static func capture() async throws -> BackupArchive {
        let search = try await ReadingSearchStore.shared.backup()
        let history = HistoryStore.shared.backup
        let ids = Set(history.browsing.map(\.id))
        let context = SettingsStore.shared.feedContextID
        let unread = FeedUnreadStore.shared.context == context ? FeedUnreadStore.shared.snapshot
            : FeedUnreadStore.Snapshot(context: context, entries: [:])
        return BackupArchive(history: history, drafts: try DraftStore.shared.backup(),
                             blacklist: BlacklistStore.shared.data, settings: BackupSettings.capture(),
                             library: FeedLibraryStore.shared.collections, unread: unread,
                             emoticons: EmoticonStore.shared.backup, search: search.filter { ids.contains($0.threadId) })
    }

    static func restore(_ archive: BackupArchive, merge: Bool) async throws {
        guard !FeedViewModel.shared.isRestoring else { return }
        try archive.validate()
        let background = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        FeedViewModel.shared.beginRestore()
        HistoryStore.shared.beginRestore()
        defer {
            HistoryStore.shared.finishRestore()
            FeedViewModel.shared.finishRestore()
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
        let original = try await capture()
        let target = merge ? archive.merging(into: original) : archive
        try target.validate()
        do {
            try await apply(target)
            SubscriptionCache.shared.clear()
        } catch {
            do { try await apply(original) } catch { throw BackupError.rollbackFailed }
            throw BackupError.restoreFailed
        }
    }

    private static func apply(_ archive: BackupArchive) async throws {
        try await ReadingSearchStore.shared.restore(archive.search)
        try DraftStore.shared.restore(archive.drafts)
        try HistoryStore.shared.restore(archive.history)
        try BlacklistStore.shared.restore(archive.blacklist)
        try FeedLibraryStore.shared.restore(archive.library)
        try FeedUnreadStore.shared.restore(archive.unread)
        BackupSettings.apply(archive.settings)
        try EmoticonStore.shared.restore(archive.emoticons)
    }
}
