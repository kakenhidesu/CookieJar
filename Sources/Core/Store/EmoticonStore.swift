import Foundation
import SwiftUI

struct Emoticon: Codable, Identifiable, Hashable {
    var id: String { "\(group.rawValue)|\(name)" }
    var name: String
    var text: String
    var group: EmoticonGroup = .custom
}

extension Emoticon {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        text = try c.decode(String.self, forKey: .text)
        group = (try? c.decode(EmoticonGroup.self, forKey: .group)) ?? .custom
    }
}

final class EmoticonStore: ObservableObject {
    static let shared = EmoticonStore()

    @Published private(set) var custom: [Emoticon] = []
    @Published private(set) var sections: [(group: EmoticonGroup, items: [Emoticon])] = []
    @Published private(set) var recent: [Emoticon] = []
    @Published private(set) var favorites: [Emoticon] = []
    private var favoriteIDs: [String] = []

    var sortByRecent: Bool {
        get { UserDefaults.standard.object(forKey: "emoticon.sortByRecent") as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "emoticon.sortByRecent")
            rebuild()
        }
    }

    private var lastUsed: [String: Date] = [:]

    struct Backup: Codable {
        var custom: [Emoticon]
        var lastUsed: [String: Date]
        var favoriteIDs: [String]

        init(custom: [Emoticon], lastUsed: [String: Date], favoriteIDs: [String] = []) {
            self.custom = custom
            self.lastUsed = lastUsed
            self.favoriteIDs = favoriteIDs
        }

        private enum CodingKeys: String, CodingKey { case custom, lastUsed, favoriteIDs }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            custom = try c.decode([Emoticon].self, forKey: .custom)
            lastUsed = try c.decode([String: Date].self, forKey: .lastUsed)
            favoriteIDs = try c.decodeIfPresent([String].self, forKey: .favoriteIDs) ?? []
        }
    }
    var backup: Backup { Backup(custom: custom, lastUsed: lastUsed, favoriteIDs: favoriteIDs) }

    func restore(_ backup: Backup) throws {
        guard customStore.saveNowChecked(backup.custom), usageStore.saveNowChecked(backup.lastUsed),
              favoritesStore.saveNowChecked(backup.favoriteIDs) else {
            throw CocoaError(.fileWriteUnknown)
        }
        custom = backup.custom
        lastUsed = backup.lastUsed
        favoriteIDs = backup.favoriteIDs
        rebuild()
    }

    private let customStore = JSONStore<[Emoticon]>(filename: "emoticons.json")
    private let usageStore = JSONStore<[String: Date]>(filename: "emoticon_usage.json")
    private let favoritesStore = JSONStore<[String]>(filename: "emoticon_favorites.json")

    private init() {
        custom = customStore.load() ?? []
        lastUsed = usageStore.load() ?? [:]
        favoriteIDs = favoritesStore.load() ?? []
        rebuild()
    }

    private func rebuild() {
        let all = EmoticonData.all + custom
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        favoriteIDs = favoriteIDs.filter { byID[$0] != nil && seen.insert($0).inserted }
        favorites = favoriteIDs.compactMap { byID[$0] }
        recent = sortByRecent
            ? all.filter { lastUsed[$0.name] != nil }
                 .sorted { (lastUsed[$0.name] ?? .distantPast) > (lastUsed[$1.name] ?? .distantPast) }
                 .prefix(16)
                 .map { $0 }
            : []

        var result: [(EmoticonGroup, [Emoticon])] = [
            (.official, EmoticonData.official),
            (.blueIsland, EmoticonData.blueIsland),
        ]
        if !custom.isEmpty { result.append((.custom, custom)) }
        sections = result.map { (group: $0.0, items: $0.1) }
    }

    func markUsed(_ e: Emoticon) {
        lastUsed[e.name] = Date()
        usageStore.save(lastUsed)
        rebuild()
    }

    func isFavorite(_ e: Emoticon) -> Bool { favoriteIDs.contains(e.id) }

    func toggleFavorite(_ e: Emoticon) {
        if isFavorite(e) { favoriteIDs.removeAll { $0 == e.id } }
        else { favoriteIDs.append(e.id) }
        favoritesStore.saveNow(favoriteIDs)
        rebuild()
    }

    @discardableResult
    @MainActor
    func saveCustom(original: Emoticon?, name: String, text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = Emoticon(name: label.isEmpty ? String(text.prefix(6)) : label, text: text, group: .custom)
        let index = original.flatMap { custom.firstIndex(of: $0) }
        guard original == nil || index != nil else { return false }
        guard !custom.enumerated().contains(where: { $0.offset != index && $0.element.id == item.id }) else {
            Toast.shared.error("已有同名颜文字")
            return false
        }
        if let index {
            let old = custom[index]
            custom[index] = item
            favoriteIDs = favoriteIDs.map { $0 == old.id ? item.id : $0 }
            if let date = lastUsed[old.name] {
                lastUsed[item.name] = max(lastUsed[item.name] ?? .distantPast, date)
                usageStore.save(lastUsed)
            }
        } else {
            custom.append(item)
        }
        customStore.saveNow(custom)
        favoritesStore.saveNow(favoriteIDs)
        rebuild()
        return true
    }

    func removeCustom(_ e: Emoticon) {
        custom.removeAll { $0.name == e.name && $0.text == e.text }
        customStore.saveNow(custom)
        favoriteIDs.removeAll { $0 == e.id }
        favoritesStore.saveNow(favoriteIDs)
        rebuild()
    }
}
