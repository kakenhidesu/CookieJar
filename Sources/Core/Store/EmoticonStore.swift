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

    var sortByRecent: Bool {
        get { UserDefaults.standard.object(forKey: "emoticon.sortByRecent") as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "emoticon.sortByRecent")
            rebuild()
        }
    }

    private var lastUsed: [String: Date] = [:]

    private let customStore = JSONStore<[Emoticon]>(filename: "emoticons.json")
    private let usageStore = JSONStore<[String: Date]>(filename: "emoticon_usage.json")

    private init() {
        custom = customStore.load() ?? []
        lastUsed = usageStore.load() ?? [:]
        rebuild()
    }

    private func rebuild() {
        let all = EmoticonData.all + custom
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

    func addCustom(name: String, text: String) {
        guard !text.isEmpty else { return }
        custom.append(Emoticon(name: name.isEmpty ? String(text.prefix(6)) : name,
                               text: text,
                               group: .custom))
        customStore.save(custom)
        rebuild()
    }

    func removeCustom(_ e: Emoticon) {
        custom.removeAll { $0.name == e.name && $0.text == e.text }
        customStore.save(custom)
        rebuild()
    }
}
