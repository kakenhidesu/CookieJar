import Foundation

struct XDAPI {
    static let shared = XDAPI()

    private var http: XDHTTP { XDHTTP.shared }
    private var urls: XDURLs { XDURLs.shared }

    func refreshEndpoints() async {
        let session = await http.rawSession
        await urls.refreshEndpoints(session: session)
    }

    func setUseBackupAPI(_ on: Bool) {
        urls.setUseBackupAPI(on)
    }

    func notice() async throws -> XDNotice {
        let data = try await http.get(XDURLs.noticeURL)
        guard let obj = try XDJSON.object(data) as? [String: Any],
              let content = obj["content"] as? String else {
            throw XDError.decode("公告格式错误")
        }
        let dateKey = XDJSON.int(obj["date"]).map(String.init) ?? ""
        return XDNotice(content: content,
                        dateKey: dateKey,
                        isEnabled: (obj["enable"] as? Bool) ?? false)
    }

    func forumList(cookie: String? = nil) async throws -> ForumListResult {
        let data = try await http.get(urls.forumListURL, cookie: cookie)
        let decoded = try XDJSON.object(data)
        try XDJSON.checkError(decoded)
        guard let groups = decoded as? [[String: Any]] else { throw XDError.decode("版块列表格式错误") }

        var groupList: [ForumGroup] = []
        var forums: [Forum] = []
        var timelines: [Timeline] = []
        for g in groups {
            groupList.append(ForumGroup(json: g))
            for f in (g["forums"] as? [[String: Any]] ?? []) {
                let id = XDJSON.int(f["id"]) ?? 0
                if id < 0 {
                    timelines.append(Timeline(id: id,
                                              name: f["name"] as? String ?? "未知时间线",
                                              message: f["msg"] as? String ?? ""))
                } else {
                    forums.append(Forum(json: f))
                }
            }
        }
        return ForumListResult(groups: groupList, forums: forums, timelines: timelines)
    }

    func timelineList(cookie: String? = nil) async throws -> [Timeline] {
        let data = try await http.get(urls.timelineListURL, cookie: cookie)
        let decoded = try XDJSON.object(data)
        try XDJSON.checkError(decoded)
        guard let arr = decoded as? [[String: Any]] else { throw XDError.decode("时间线格式错误") }
        return arr.map(Timeline.init(json:))
    }

    func forumThreads(forumId: Int, page: Int, cookie: String? = nil) async throws -> [ForumThread] {
        guard forumId > 0 else { throw XDError.api("版块 ID 要大于 0") }
        let data = try await http.get(urls.forumURL(forumId, page: max(1, page)), cookie: cookie)
        return try parseForumThreads(data)
    }

    func timelineThreads(timelineId: Int, page: Int, cookie: String? = nil) async throws -> [ForumThread] {
        let data = try await http.get(urls.timelineURL(timelineId, page: max(1, page)), cookie: cookie)
        return try parseForumThreads(data)
    }

    private func parseForumThreads(_ data: Data) throws -> [ForumThread] {
        let decoded = try XDJSON.object(data)
        try XDJSON.checkError(decoded)
        guard let arr = decoded as? [[String: Any]] else { throw XDError.decode("串列表格式错误") }
        return arr.map { item in
            ForumThread(mainPost: XDPost(json: item),
                        recentReplies: (item["Replies"] as? [[String: Any]] ?? []).map { XDPost(json: $0) },
                        remainReplies: XDJSON.int(item["RemainReplies"]))
        }
    }

    func thread(mainPostId: Int, page: Int, onlyPo: Bool = false, cookie: String? = nil) async throws -> ThreadPage {
        guard mainPostId > 0 else { throw XDError.api("主串 ID 要大于 0") }
        let p = max(1, page)
        let url = onlyPo ? urls.onlyPoURL(mainPostId, page: p) : urls.threadURL(mainPostId, page: p)
        let data = try await http.get(url, cookie: cookie)
        let decoded = try XDJSON.object(data)
        try XDJSON.checkError(decoded)
        guard let obj = decoded as? [String: Any] else { throw XDError.decode("串内容格式错误") }

        let mainPost = XDPost(json: obj)
        var tip: XDPost?
        var replies: [XDPost] = []
        let raw = obj["Replies"] as? [[String: Any]] ?? []
        for (i, r) in raw.enumerated() {
            if i == 0, r["fid"] == nil {
                var t = XDPost(json: r, kind: .tip)
                t.id = XDJSON.int(r["id"]) ?? 9_999_999
                t.userHash = "Tips"
                t.title = "Tips"
                t.isAdmin = true
                if t.postTime == .distantPast {
                    t.postTime = XDTime.parseServer("2099-01-01(五)00:00:01")
                }
                tip = t
            } else {
                replies.append(XDPost(json: r))
            }
        }
        return ThreadPage(mainPost: mainPost, replies: replies, tip: tip)
    }

    func reference(postId: Int, cookie: String? = nil) async throws -> XDPost {
        guard postId > 0 else { throw XDError.api("串的 ID 要大于 0") }

        if let data = try? await http.get(urls.htmlReferenceURL(postId), cookie: cookie),
           let post = HTMLScrape.parseReference(data.utf8String, postId: postId) {
            return post
        }

        let data = try await http.get(urls.referenceURL(postId), cookie: cookie)
        let decoded = try XDJSON.object(data)
        try XDJSON.checkError(decoded)
        guard let obj = decoded as? [String: Any] else { throw XDError.decode("引用格式错误") }
        return XDPost(json: obj, kind: .reference)
    }

    func feed(uuid: String, page: Int, cookie: String? = nil) async throws -> [XDPost] {
        let data = try await http.get(urls.feedURL(uuid, page: max(1, page)), cookie: cookie)
        let decoded = try XDJSON.object(data)
        try XDJSON.checkError(decoded)
        guard let arr = decoded as? [[String: Any]] else { throw XDError.decode("订阅格式错误") }
        return arr.map { item in
            var p = XDPost(json: item, kind: .feed)
            p.mainPostId = p.id
            return p
        }
    }

    func addFeed(uuid: String, mainPostId: Int, cookie: String? = nil) async throws {
        try await feedAction(urls.addFeedURL(uuid, mainPostId), cookie: cookie)
    }

    func deleteFeed(uuid: String, mainPostId: Int, cookie: String? = nil) async throws {
        try await feedAction(urls.delFeedURL(uuid, mainPostId), cookie: cookie)
    }

    private func feedAction(_ url: URL, cookie: String?) async throws {
        let data = try await http.get(url, cookie: cookie)
        let decoded = try XDJSON.object(data)
        if let s = decoded as? String {
            guard s.contains("成功") else { throw XDError.api(s) }
            return
        }
        try XDJSON.checkError(decoded)
    }

    func htmlFeed(page: Int, cookie: String) async throws -> [XDPost] {
        let data = try await http.get(urls.htmlFeedURL(page: max(1, page)), cookie: cookie)
        return HTMLScrape.parseFeeds(data.utf8String)
    }

    func addHTMLFeed(mainPostId: Int, cookie: String) async throws {
        let data = try await http.get(urls.addHTMLFeedURL(mainPostId), cookie: cookie)
        try HTMLScrape.checkResult(data.utf8String)
    }

    func deleteHTMLFeed(mainPostId: Int, cookie: String) async throws {
        let data = try await http.get(urls.delHTMLFeedURL(mainPostId), cookie: cookie)
        try HTMLScrape.checkResult(data.utf8String)
    }

    func postThread(forumId: Int,
                    content: String,
                    name: String? = nil,
                    title: String? = nil,
                    watermark: Bool = false,
                    image: XDImagePayload? = nil,
                    cookie: String) async throws {
        guard forumId > 0 else { throw XDError.api("版块 ID 要大于 0") }
        try await submit(url: urls.postThreadURL, target: ("fid", forumId), content: content,
                         name: name, title: title, watermark: watermark, image: image, cookie: cookie)
    }

    func replyThread(mainPostId: Int,
                     content: String,
                     name: String? = nil,
                     title: String? = nil,
                     watermark: Bool = false,
                     image: XDImagePayload? = nil,
                     cookie: String) async throws {
        guard mainPostId > 0 else { throw XDError.api("主串 ID 要大于 0") }
        try await submit(url: urls.replyThreadURL, target: ("resto", mainPostId), content: content,
                         name: name, title: title, watermark: watermark, image: image, cookie: cookie)
    }

    private func submit(url: URL,
                        target: (field: String, id: Int),
                        content: String,
                        name: String?,
                        title: String?,
                        watermark: Bool,
                        image: XDImagePayload?,
                        cookie: String) async throws {
        guard !content.isEmpty || image != nil else { throw XDError.api("不发图时串的内容不能为空") }

        var mp = Multipart()
        mp.add(target.field, "\(target.id)")
        mp.add("content", content)
        if let name, !name.isEmpty { mp.add("name", name) }
        if let title, !title.isEmpty { mp.add("title", title) }
        if watermark { mp.add("water", "true") }
        if let image { mp.addFile("image", data: image.data, filename: image.filename, mime: image.mime) }

        let data = try await http.postMultipart(url, multipart: mp, cookie: cookie)
        try HTMLScrape.checkResult(data.utf8String)
    }

    func lastPost(cookie: String) async throws -> XDPost? {
        let data = try await http.get(urls.lastPostURL, cookie: cookie)
        let decoded = try XDJSON.object(data)
        guard let obj = decoded as? [String: Any], XDJSON.int(obj["id"]) != nil else { return nil }
        return XDPost(json: obj)
    }

    func verifyImage() async throws -> Data {
        try await http.get(urls.verifyImageURL)
    }

    func login(email: String, password: String, verify: String) async throws {
        guard await http.hasSession else { throw XDError.api("请先加载验证码") }
        let (data, setCookie) = try await http.postFormWithHeaders(
            urls.loginURL, fields: ["email": email, "password": password, "verify": verify])
        try HTMLScrape.checkResult(data.utf8String)
        guard let setCookie, setCookie.contains("memberUserspapapa") else {
            throw XDError.api("登录失败，请检查邮箱、密码和验证码")
        }
        let pair = setCookie
            .components(separatedBy: ";")
            .first(where: { $0.contains("memberUserspapapa") })?
            .trimmingCharacters(in: .whitespaces)
        await http.setUserCookie(pair)
    }

    func logout() async {
        await http.setUserCookie(nil)
    }

    func cookiesList() async throws -> CookiesListInfo {
        guard let userCookie = await http.userCookie else { throw XDError.needLogin }
        let data = try await http.get(urls.cookieListURL, cookie: userCookie)
        guard let info = HTMLScrape.parseCookiesList(data.utf8String) else {
            throw XDError.api("获取饼干列表失败，可能登录已过期")
        }
        return info
    }

    func exportCookie(id: Int) async throws -> XDCookie {
        guard let userCookie = await http.userCookie else { throw XDError.needLogin }
        let data = try await http.get(urls.exportCookieURL(id), cookie: userCookie)
        guard let c = HTMLScrape.parseCookieExport(data.utf8String, id: id) else {
            throw XDError.api("获取饼干失败")
        }
        return c
    }

    func search(query: String, page: Int, cookie: String? = nil) async throws -> [XDPost] {
        let data = try await http.get(urls.searchURL(query, page: max(1, page)), cookie: cookie)
        let decoded = try XDJSON.object(data)
        try XDJSON.checkError(decoded)
        guard let obj = decoded as? [String: Any],
              let hits = obj["hits"] as? [String: Any],
              let list = hits["hits"] as? [[String: Any]] else {
            throw XDError.api("搜索接口返回异常（官方搜索可能已下线）")
        }
        return list.compactMap { hit in
            guard let source = hit["_source"] as? [String: Any] else { return nil }
            let id = Int(hit["_id"] as? String ?? "") ?? XDJSON.int(source["id"]) ?? 0
            guard id > 0 else { return nil }
            var p = XDPost(json: source)
            p.id = id
            p.mainPostId = XDJSON.int(source["resto"]).flatMap { $0 == 0 ? id : $0 } ?? id
            return p
        }
    }
}
