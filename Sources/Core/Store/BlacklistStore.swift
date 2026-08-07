import Foundation
import SwiftUI

final class BlacklistStore: ObservableObject {
    static let shared = BlacklistStore()

    struct Payload: Codable {
        var users: [String: String] = [:]
        var posts: [Int: String] = [:]
        var forums: Set<Int> = []
        var keywords: [String] = []
    }

    @Published private(set) var data = Payload()
    private let store = JSONStore<Payload>(filename: "blacklist.json")

    private init() {
        data = store.load() ?? Payload()
    }

    private func persist() { store.save(data) }

    func isBlocked(user hash: String) -> Bool { data.users[hash] != nil }
    func block(user hash: String, note: String = "") {
        guard !hash.isEmpty else { return }
        data.users[hash] = note
        persist()
    }
    func unblock(user hash: String) { data.users.removeValue(forKey: hash); persist() }

    func isBlocked(post id: Int) -> Bool { data.posts[id] != nil }
    func block(post id: Int, title: String = "") { data.posts[id] = title; persist() }
    func unblock(post id: Int) { data.posts.removeValue(forKey: id); persist() }

    func isBlocked(forum id: Int) -> Bool { data.forums.contains(id) }
    func toggle(forum id: Int) {
        if data.forums.contains(id) { data.forums.remove(id) } else { data.forums.insert(id) }
        persist()
    }

    func addKeyword(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !data.keywords.contains(w) else { return }
        data.keywords.append(w)
        persist()
    }
    func removeKeyword(_ word: String) {
        data.keywords.removeAll { $0 == word }
        persist()
    }

    func shouldHide(_ post: XDPost) -> Bool {
        if isBlocked(user: post.userHash) { return true }
        if isBlocked(post: post.mainPostId ?? post.id) { return true }
        if let fid = post.forumId, isBlocked(forum: fid) { return true }
        if !data.keywords.isEmpty {
            let text = XDContent.plainText(post.content) + post.title + post.name
            for k in data.keywords where text.localizedCaseInsensitiveContains(k) { return true }
        }
        return false
    }

    func clearAll() {
        data = Payload()
        store.saveNow(data)
    }
}
