import Foundation
import Combine

final class FeedLibraryStore: ObservableObject {
    static let shared = FeedLibraryStore()

    struct Group: Codable, Identifiable {
        var id = UUID()
        var name: String
    }
    struct Collection: Codable {
        var groups: [Group] = []
        var pinned: Set<Int> = []
        var assignments: [Int: UUID] = [:]
    }
    typealias Snapshot = [String: Collection]
    @Published private(set) var collections: Snapshot
    private let disk = JSONStore<Snapshot>(filename: "feed-library.json")

    private init() { collections = disk.load() ?? [:] }

    var current: Collection { collections[SettingsStore.shared.feedContextID] ?? Collection() }

    func togglePin(_ id: Int) {
        update { if !$0.pinned.insert(id).inserted { $0.pinned.remove(id) } }
    }

    func assign(_ id: Int, to group: UUID?) {
        assign([id], to: group)
    }

    func assign(_ ids: Set<Int>, to group: UUID?) {
        guard !ids.isEmpty else { return }
        update { collection in
            for id in ids { collection.assignments[id] = group }
        }
    }

    func saveGroup(id: UUID = UUID(), name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update {
            if let index = $0.groups.firstIndex(where: { $0.id == id }) {
                $0.groups[index].name = name
            } else { $0.groups.append(Group(id: id, name: name)) }
        }
    }

    func removeGroup(_ id: UUID) {
        update {
            $0.groups.removeAll { $0.id == id }
            $0.assignments = $0.assignments.filter { $0.value != id }
        }
    }

    func removeThread(_ id: Int) {
        update { $0.pinned.remove(id); $0.assignments.removeValue(forKey: id) }
    }

    func restore(_ snapshot: Snapshot) throws {
        guard disk.saveNowChecked(snapshot) else { throw CocoaError(.fileWriteUnknown) }
        collections = snapshot
    }

    private func update(_ change: (inout Collection) -> Void) {
        let context = SettingsStore.shared.feedContextID
        var collection = current
        change(&collection)
        collections[context] = collection
        disk.saveNow(collections)
    }
}
