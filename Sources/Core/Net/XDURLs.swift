import Foundation

final class XDURLs {
    static let shared = XDURLs()

    static let originBase = URL(string: "https://www.nmbxd.com/")!
    static let fallbackBase = URL(string: "https://www.nmbxd1.com/")!
    static let fallbackCDN = URL(string: "https://image.nmb.best/")!
    static let fallbackBackupAPI = URL(string: "https://api.nmb.best/")!
    static let noticeURL = URL(string: "https://nmb.ovear.info/nmb-notice.json")!

    private let lock = NSLock()
    private var _base = XDURLs.fallbackBase
    private var _cdn = XDURLs.fallbackCDN
    private var _backupAPI = XDURLs.fallbackBackupAPI
    private var _useBackupAPI = false

    private init() {
        let defaults = UserDefaults.standard
        if let s = defaults.string(forKey: "xd.base"), let u = URL(string: s), u.host != nil { _base = u }
        if let s = defaults.string(forKey: "xd.cdn"), let u = URL(string: s), u.host != nil { _cdn = u }
        if let s = defaults.string(forKey: "xd.backup"), let u = URL(string: s), u.host != nil { _backupAPI = u }
        _useBackupAPI = defaults.bool(forKey: "xd.useBackupAPI")
    }

    private func read<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var base: URL { read { _base } }
    var cdn: URL { read { _cdn } }
    var backupAPI: URL { read { _backupAPI } }
    var useBackupAPI: Bool { read { _useBackupAPI } }

    var apiBase: URL { read { _useBackupAPI ? _backupAPI : _base } }

    func setUseBackupAPI(_ value: Bool) {
        lock.lock()
        _useBackupAPI = value
        lock.unlock()
        UserDefaults.standard.set(value, forKey: "xd.useBackupAPI")
    }

    func isBase(_ url: URL) -> Bool { url.host == base.host }
    func isBackup(_ url: URL) -> Bool { url.host == backupAPI.host }

    private func update(base: URL?, cdn: URL?, backup: URL?) {
        lock.lock()
        if let base { _base = base }
        if let cdn { _cdn = cdn }
        if let backup { _backupAPI = backup }
        lock.unlock()

        let defaults = UserDefaults.standard
        if let base { defaults.set(base.absoluteString, forKey: "xd.base") }
        if let cdn { defaults.set(cdn.absoluteString, forKey: "xd.cdn") }
        if let backup { defaults.set(backup.absoluteString, forKey: "xd.backup") }
    }

    private func url(_ root: URL, _ path: String, _ query: [String: String]? = nil) -> URL {
        guard var comps = URLComponents(url: root, resolvingAgainstBaseURL: false) else {
            return XDURLs.fallbackBase.appendingPathComponent(path)
        }
        comps.path = "/" + path
        if let query, !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        } else {
            comps.queryItems = nil
        }
        return comps.url ?? XDURLs.fallbackBase.appendingPathComponent(path)
    }

    private func api(_ path: String, _ query: [String: String]? = nil) -> URL { url(apiBase, path, query) }
    private func web(_ path: String, _ query: [String: String]? = nil) -> URL { url(base, path, query) }

    var forumListURL: URL { api("Api/getForumList") }
    var timelineListURL: URL { api("Api/getTimelineList") }
    func forumURL(_ id: Int, page: Int) -> URL { api("Api/showf", ["id": "\(id)", "page": "\(page)"]) }
    func timelineURL(_ id: Int, page: Int) -> URL { api("Api/timeline", ["id": "\(id)", "page": "\(page)"]) }
    func threadURL(_ id: Int, page: Int) -> URL { api("Api/thread", ["id": "\(id)", "page": "\(page)"]) }
    func onlyPoURL(_ id: Int, page: Int) -> URL { api("Api/po", ["id": "\(id)", "page": "\(page)"]) }
    func referenceURL(_ id: Int) -> URL { api("Api/ref", ["id": "\(id)"]) }
    func feedURL(_ uuid: String, page: Int) -> URL { api("Api/feed", ["uuid": uuid, "page": "\(page)"]) }
    func addFeedURL(_ uuid: String, _ tid: Int) -> URL { api("Api/addFeed", ["uuid": uuid, "tid": "\(tid)"]) }
    func delFeedURL(_ uuid: String, _ tid: Int) -> URL { api("Api/delFeed", ["uuid": uuid, "tid": "\(tid)"]) }
    func searchURL(_ q: String, page: Int) -> URL { api("Api/search", ["q": q, "pageNo": "\(page)"]) }

    var lastPostURL: URL { web("Api/getLastPost") }
    var postThreadURL: URL { web("Home/Forum/doPostThread.html") }
    var replyThreadURL: URL { web("Home/Forum/doReplyThread.html") }
    var verifyImageURL: URL { web("Member/User/Index/verify.html") }
    var loginURL: URL { web("Member/User/Index/login.html") }
    var cookieListURL: URL { web("Member/User/Cookie/index.html") }
    func htmlReferenceURL(_ id: Int) -> URL { web("Home/Forum/ref", ["id": "\(id)"]) }
    func htmlFeedURL(page: Int) -> URL { web("Forum/feed/page/\(page).html") }
    func addHTMLFeedURL(_ tid: Int) -> URL { web("Home/Forum/addFeed/tid/\(tid).html") }
    func delHTMLFeedURL(_ tid: Int) -> URL { web("Home/Forum/delFeed/tid/\(tid).html") }
    func exportCookieURL(_ cookieId: Int) -> URL { web("Member/User/Cookie/export/id/\(cookieId).html") }

    func webThreadURL(_ id: Int, page: Int? = nil) -> URL {
        page.map { web("t/\(id)", ["page": "\($0)"]) } ?? web("t/\(id)")
    }

    func thumb(_ file: String) -> URL { url(cdn, "thumb/\(file)") }
    func image(_ file: String) -> URL { url(cdn, "image/\(file)") }

    func refreshEndpoints(session: URLSession) async {
        var probe = URLRequest(url: XDURLs.originBase)
        probe.httpMethod = "HEAD"
        var newBase: URL?
        if let (_, resp) = try? await session.data(for: probe),
           let host = (resp as? HTTPURLResponse)?.url?.host {
            newBase = URL(string: "https://\(host)/")
        }
        let effectiveBase = newBase ?? base

        async let cdnData = XDURLs.fetch(session, url(effectiveBase, "Api/getCdnPath"))
        async let backupData = XDURLs.fetch(session, url(effectiveBase, "Api/backupUrl"))

        var newCDN: URL?
        if let data = await cdnData,
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let s = arr.first?["url"] as? String, let u = URL(string: s) {
            newCDN = u
        }

        var newBackup: URL?
        if let data = await backupData,
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
           let s = arr.first, let u = URL(string: s) {
            newBackup = u
        }

        update(base: newBase, cdn: newCDN, backup: newBackup)
    }

    private static func fetch(_ session: URLSession, _ url: URL) async -> Data? {
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        return data
    }
}
