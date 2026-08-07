import Foundation
import SwiftUI

struct Draft: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var name: String = ""
    var content: String = ""
    var updatedAt: Date = Date()

    var preview: String {
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (title.isEmpty ? "（空草稿）" : title) : String(t.prefix(80))
    }
}

final class DraftStore: ObservableObject {
    static let shared = DraftStore()

    @Published private(set) var drafts: [Draft] = []
    private let store = JSONStore<[Draft]>(filename: "drafts.json")

    private init() { drafts = store.load() ?? [] }

    func save(_ draft: Draft) {
        var d = draft
        d.updatedAt = Date()
        if let idx = drafts.firstIndex(where: { $0.id == d.id }) {
            drafts[idx] = d
        } else {
            drafts.insert(d, at: 0)
        }
        if drafts.count > 200 { drafts = Array(drafts.prefix(200)) }
        store.save(drafts)
    }

    func remove(_ draft: Draft) {
        drafts.removeAll { $0.id == draft.id }
        store.save(drafts)
    }

    func remove(at offsets: IndexSet) {
        drafts.remove(atOffsets: offsets)
        store.save(drafts)
    }
}
