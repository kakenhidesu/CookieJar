import Foundation
import SwiftUI

struct XDNotice: Codable, Equatable {
    var content: String
    var dateKey: String
    var isEnabled: Bool

    var day: String {
        guard dateKey.count >= 8 else { return "" }
        let s = Array(dateKey)
        return "\(String(s[0..<4]))-\(String(s[4..<6]))-\(String(s[6..<8]))"
    }
}

final class NoticeStore: ObservableObject {
    static let shared = NoticeStore()

    @Published private(set) var notice: XDNotice?
    @Published var shouldShow: Bool {
        didSet { UserDefaults.standard.set(shouldShow, forKey: "notice.shouldShow") }
    }
    @Published private(set) var isLoading = false

    private let store = JSONStore<[XDNotice]>(filename: "notice.json")

    private init() {
        shouldShow = UserDefaults.standard.bool(forKey: "notice.shouldShow")
        notice = store.load()?.first
    }

    var hasContent: Bool { !(notice?.content.isEmpty ?? true) }

    @MainActor
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let fetched = try? await XDAPI.shared.notice() else {
            LaunchLog.mark("公告获取失败")
            return
        }
        guard fetched.isEnabled, !fetched.content.isEmpty else { return }

        if fetched.content != notice?.content || fetched.dateKey != notice?.dateKey {
            notice = fetched
            store.saveNow([fetched])
            shouldShow = true
            LaunchLog.mark("有新公告 \(fetched.day)")
        }
    }

    func markSeen() {
        shouldShow = false
    }
}
