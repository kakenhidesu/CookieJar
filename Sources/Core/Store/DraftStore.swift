import Foundation
import SwiftUI
import UIKit

struct Draft: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var name: String = ""
    var content: String = ""
    var updatedAt: Date = Date()
    var forumId: Int? = nil
    var replyTo: Int? = nil
    var reportPostId: Int? = nil
    var reportReason: String? = nil
    var imageFile: String? = nil

    var preview: String {
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (title.isEmpty ? (imageFile == nil ? "（空草稿）" : "[图片]") : title) : String(t.prefix(80))
    }
}

final class DraftStore: ObservableObject {
    static let shared = DraftStore()

    @Published private(set) var drafts: [Draft] = []
    private let store = JSONStore<[Draft]>(filename: "drafts.json")

    private init() { drafts = store.load() ?? [] }

    @discardableResult
    func save(_ draft: Draft) -> Bool {
        var d = draft
        d.updatedAt = Date()
        if let idx = drafts.firstIndex(where: { $0.id == d.id }) {
            drafts[idx] = d
        } else {
            drafts.insert(d, at: 0)
        }
        if drafts.count > 200 { drafts = Array(drafts.prefix(200)) }
        guard store.saveNowChecked(drafts) else { return false }
        pruneImages(for: d.id, keeping: d.imageFile)
        return true
    }

    private func pruneImages(for draftId: UUID, keeping: String?) {
        for ext in ["png", "jpg"] {
            let name = draftId.uuidString + "." + ext
            if name == keeping { continue }
            try? FileManager.default.removeItem(at: Self.imageDir.appendingPathComponent(name))
        }
    }

    func remove(_ draft: Draft) {
        removeImage(for: draft.id)
        drafts.removeAll { $0.id == draft.id }
        store.save(drafts)
    }

    func remove(at offsets: IndexSet) {
        for idx in offsets where drafts.indices.contains(idx) {
            removeImage(for: drafts[idx].id)
        }
        drafts.remove(atOffsets: offsets)
        store.save(drafts)
    }

    private static var imageDir: URL {
        let dir = AppPaths.dataDirectory.appendingPathComponent("drafts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func saveImage(_ data: Data, isPNG: Bool, for draftId: UUID) -> String? {
        let name = draftId.uuidString + (isPNG ? ".png" : ".jpg")
        guard (try? data.write(to: Self.imageDir.appendingPathComponent(name), options: .atomic)) != nil else { return nil }
        return name
    }

    func loadImage(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: Self.imageDir.appendingPathComponent(name).path)
    }

    func removeImage(for draftId: UUID) {
        for ext in ["png", "jpg"] {
            try? FileManager.default.removeItem(at: Self.imageDir.appendingPathComponent(draftId.uuidString + "." + ext))
        }
    }
}
