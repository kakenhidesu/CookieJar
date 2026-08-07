import Foundation
import SwiftUI

final class CookieStore: ObservableObject {
    static let shared = CookieStore()

    @Published private(set) var cookies: [XDCookie] = []
    @Published var selectedHash: String? {
        didSet { UserDefaults.standard.set(selectedHash, forKey: "cookie.selected") }
    }

    private let keychainKey = "xd.cookies"

    var selected: XDCookie? {
        guard let selectedHash else { return cookies.first }
        return cookies.first(where: { $0.userHash == selectedHash }) ?? cookies.first
    }

    var cookieValue: String? { selected?.cookieValue }

    var hasCookie: Bool { selected != nil }

    private init() {
        selectedHash = UserDefaults.standard.string(forKey: "cookie.selected")
        load()
    }

    private func load() {
        guard let raw = KeychainStore.read(keychainKey),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([XDCookie].self, from: data) else { return }
        cookies = list
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cookies),
              let s = String(data: data, encoding: .utf8) else { return }
        KeychainStore.write(keychainKey, s)
    }

    @discardableResult
    func add(_ cookie: XDCookie) -> Bool {
        guard !cookie.userHash.isEmpty else { return false }
        if let idx = cookies.firstIndex(where: { $0.userHash == cookie.userHash }) {
            cookies[idx].name = cookie.name.isEmpty ? cookies[idx].name : cookie.name
            cookies[idx].remoteId = cookie.remoteId ?? cookies[idx].remoteId
            persist()
            return false
        }
        cookies.append(cookie)
        if selectedHash == nil { selectedHash = cookie.userHash }
        persist()
        return true
    }

    func remove(_ cookie: XDCookie) {
        cookies.removeAll { $0.userHash == cookie.userHash }
        if selectedHash == cookie.userHash { selectedHash = cookies.first?.userHash }
        persist()
    }

    func select(_ cookie: XDCookie?) {
        selectedHash = cookie?.userHash
    }

    func recordDisplayId(_ displayId: String) {
        let id = displayId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, let hash = selected?.userHash,
              let idx = cookies.firstIndex(where: { $0.userHash == hash }) else { return }
        var ids = cookies[idx].displayIds ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        if ids.count > 20 { ids.removeFirst(ids.count - 20) }
        cookies[idx].displayIds = ids
        persist()
    }

    func isMine(displayId: String) -> Bool {
        guard !displayId.isEmpty else { return false }
        return selected?.displayIds?.contains(displayId) ?? false
    }

    func move(from source: IndexSet, to destination: Int) {
        cookies.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    static func parse(_ raw: String) -> XDCookie? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        func fromJSON(_ data: Data) -> XDCookie? {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            guard let hash = (obj["cookie"] as? String) ?? (obj["userhash"] as? String) ?? (obj["userHash"] as? String)
            else { return nil }
            let name = obj["name"] as? String ?? hash
            return XDCookie(userHash: hash, name: name.isEmpty ? hash : name)
        }

        if text.hasPrefix("{"), let d = text.data(using: .utf8), let c = fromJSON(d) { return c }
        if let d = Data(base64Encoded: text.replacingOccurrences(of: " ", with: "+")), let c = fromJSON(d) { return c }
        if text.contains("text="),
           let comps = URLComponents(string: text),
           let t = comps.queryItems?.first(where: { $0.name == "text" })?.value,
           let d = Data(base64Encoded: t.replacingOccurrences(of: " ", with: "+")),
           let c = fromJSON(d) { return c }
        if text.count >= 8, !text.contains(" "), !text.contains("\n") {
            return XDCookie(userHash: text, name: String(text.prefix(8)))
        }
        return nil
    }

    func exportText(_ cookie: XDCookie) -> String {
        let obj: [String: Any] = ["cookie": cookie.userHash, "name": cookie.name]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return String(data: data, encoding: .utf8) ?? cookie.userHash
    }
}
