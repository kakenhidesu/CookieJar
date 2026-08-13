import SwiftUI

enum AppRoute: Hashable {
    case forum(id: Int, isTimeline: Bool)
    case thread(id: Int, page: Int, onlyPo: Bool, jumpTo: Int?)
    case searchResult(query: String)
    case drafts
    case blacklist
    case cookies
    case settings
    case forumManage
    case about
}

enum AppTab: Int, Hashable {
    case forums, feed, history, profile
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var tab: AppTab = .forums

    @Published var forumsPath: [AppRoute] = [] { didSet { syncReadingSession() } }
    @Published var feedPath: [AppRoute] = [] { didSet { syncReadingSession() } }
    @Published var historyPath: [AppRoute] = [] { didSet { syncReadingSession() } }
    @Published var profilePath: [AppRoute] = [] { didSet { syncReadingSession() } }

    private func syncReadingSession() {
        let stillInThread = [forumsPath, feedPath, historyPath, profilePath].contains { path in
            path.contains { route in
                if case .thread = route { return true }
                return false
            }
        }
        if !stillInThread { HistoryStore.shared.clearReading() }
    }

    @Published var currentForumId: Int = -1
    @Published var currentIsTimeline: Bool = true

    @Published var referencePostId: Int?
    @Published var imageViewer: ImageViewerPayload?
    @Published var compose: ComposeTarget?

    private init() {
        let s = SettingsStore.shared
        currentForumId = s.defaultForumId
        currentIsTimeline = s.defaultIsTimeline
    }

    @Published private(set) var refreshTick: [AppTab: Int] = [:]

    func reselect(_ tab: AppTab) {
        let path: [AppRoute]
        switch tab {
        case .forums: path = forumsPath
        case .feed: path = feedPath
        case .history: path = historyPath
        case .profile: path = profilePath
        }

        if path.isEmpty {
            refreshTick[tab, default: 0] += 1
        } else {
            popToRoot(tab)
        }
    }

    /// 发完回复后通知对应的串页面重新拉一次
    @Published private(set) var threadRefreshTick: [Int: Int] = [:]

    func noteReplyPosted(mainPostId: Int) {
        threadRefreshTick[mainPostId, default: 0] += 1
    }

    func noteThreadPosted() {
        refreshTick[.forums, default: 0] += 1
    }

    func popToRoot(_ tab: AppTab) {
        switch tab {
        case .forums: forumsPath.removeAll()
        case .feed: feedPath.removeAll()
        case .history: historyPath.removeAll()
        case .profile: profilePath.removeAll()
        }
    }

    func push(_ route: AppRoute) {
        switch tab {
        case .forums: forumsPath.append(route)
        case .feed: feedPath.append(route)
        case .history: historyPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func openThread(_ id: Int, page: Int = 1, onlyPo: Bool = false, jumpTo: Int? = nil) {
        push(.thread(id: id, page: page, onlyPo: onlyPo, jumpTo: jumpTo))
    }

    @discardableResult
    func restoreLastThreadIfNeeded() -> Bool {
        guard SettingsStore.shared.restoreLastThread else {
            LaunchLog.mark("恢复上次的串：设置已关闭")
            return false
        }
        guard let session = HistoryStore.shared.lastSession, session.mainPostId > 0 else {
            LaunchLog.mark("恢复上次的串：没有记录")
            return false
        }
        guard forumsPath.isEmpty else { return false }

        tab = .forums
        forumsPath = [.thread(id: session.mainPostId,
                              page: session.page,
                              onlyPo: session.onlyPo,
                              jumpTo: session.postId)]
        return true
    }

    func openForum(id: Int, isTimeline: Bool) {
        currentForumId = id
        currentIsTimeline = isTimeline
        tab = .forums
        forumsPath.removeAll()
    }

    func handle(url: URL) -> Bool {
        if let id = XDContent.postId(fromRefURL: url) {
            referencePostId = id
            return true
        }
        guard let host = url.host else { return false }
        guard host.range(of: "^(www\\.)?nmbxd[0-9]*\\.com$", options: .regularExpression) != nil else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> Int? { query.first(where: { $0.name == name })?.value.flatMap(Int.init) }

        if parts.count >= 2, parts[0].lowercased() == "t", let id = Int(parts[1].replacingOccurrences(of: ".html", with: "")) {
            openThread(id, page: q("page") ?? 1, jumpTo: q("r"))
            return true
        }
        if parts.count >= 2, parts[0].lowercased() == "f" {
            let name = parts[1]
            if let forum = ForumStore.shared.forums.first(where: { $0.name == name || $0.displayName == name }) {
                openForum(id: forum.id, isTimeline: false)
                return true
            }
        }
        if parts.count >= 3, parts[0].lowercased() == "forum" {
            let kind = parts[1].lowercased()
            var params: [String: String] = [:]
            var i = 2
            while i + 1 < parts.count {
                params[parts[i]] = parts[i + 1].replacingOccurrences(of: ".html", with: "")
                i += 2
            }
            let id = Int(params["id"] ?? "") ?? q("id")
            let page = Int(params["page"] ?? "") ?? q("page") ?? 1
            switch kind {
            case "thread", "thread.html":
                if let id { openThread(id, page: page, jumpTo: q("r")); return true }
            case "po", "po.html":
                if let id { openThread(id, page: page, onlyPo: true, jumpTo: q("r")); return true }
            case "timeline", "timeline.html":
                openForum(id: id ?? -1, isTimeline: true); return true
            case "showf", "showf.html":
                if let id { openForum(id: id, isTimeline: false); return true }
            default: break
            }
        }
        return false
    }
}

struct ImageViewerPayload: Identifiable {
    var id: String { images.map(\.absoluteString).joined() + "\(index)" }
    var images: [URL]
    var index: Int
}

enum ComposeTarget: Identifiable {
    case newThread(forumId: Int?)
    case reply(mainPostId: Int, quote: String?)
    case draft(Draft)
    case report(postId: Int)

    var id: String {
        switch self {
        case .newThread(let f): return "new-\(f.map(String.init) ?? "none")"
        case .reply(let m, _): return "reply-\(m)"
        case .draft(let d): return "draft-\(d.id)"
        case .report(let p): return "report-\(p)"
        }
    }
}

enum ReportInfo {
    static let dutyRoomForumId = 18

    static let reasons = ["黄赌毒", "政治敏感", "谣言欺诈", "广告q群",
                          "引战辱骂", "串版", "错字自删", "错饼自删"]
}
