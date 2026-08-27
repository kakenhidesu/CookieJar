import Foundation

enum HTMLScrape {

    private static let regexCache = NSCache<NSString, NSRegularExpression>()

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue)|\(pattern)" as NSString
        if let cached = regexCache.object(forKey: key) { return cached }
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCache.setObject(re, forKey: key)
        return re
    }

    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> [[String?]] {
        guard let re = regex(pattern, options) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
        }
    }

    static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        matches(pattern, in: text).first
    }

    static func capture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let m = matches(pattern, in: text).first, m.count > group else { return nil }
        return m[group]
    }

    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                   "&apos;": "'", "&nbsp;": " ", "&#x27;": "'", "&#x2F;": "/"]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        for m in matches("&#(\\d+);", in: out) {
            guard let whole = m[0], let code = m[1].flatMap({ UInt32($0) }),
                  let scalar = Unicode.Scalar(code) else { continue }
            out = out.replacingOccurrences(of: whole, with: String(Character(scalar)))
        }
        return out
    }

    @discardableResult
    static func checkResult(_ html: String) throws -> String? {
        if let body = capture("<p class=\"error\">(.*?)</p>", in: html) {
            throw XDError.api(plainText(body))
        }
        if let body = capture("<p class=\"success\">(.*?)</p>", in: html) {
            return plainText(body)
        }
        if let body = capture("<div class=\"[^\"]*error[^\"]*\">(.*?)</div>", in: html) {
            let t = plainText(body)
            if !t.isEmpty { throw XDError.api(t) }
        }
        return nil
    }

    static func parseFeeds(_ html: String) -> [XDPost] {
        var posts: [XDPost] = []
        let items = matches("<div class=\"h-threads-item uk-clearfix\"[^>]*>(.*?)<div class=\"h-threads-tips\"", in: html)
        let blocks: [String] = items.isEmpty
            ? matches("<div class=\"h-threads-item[^\"]*\"[^>]*>(.*?)(?=<div class=\"h-threads-item|<ul class=\"uk-pagination|\\z)", in: html).compactMap { $0[1] }
            : items.compactMap { $0[1] }

        for block in blocks {
            guard let post = parseThreadItem(block) else { continue }
            posts.append(post)
        }

        return posts
    }

    static func parseReference(_ html: String, postId: Int) -> XDPost? {
        guard var post = parseThreadItem(html, kind: .reference) else { return nil }
        if post.id <= 0 { post.id = postId }
        return post
    }

    static func parseThreadItem(_ block: String, kind: PostKind = .feed) -> XDPost? {
        let anchor = matches("<a([^>]*h-threads-info-id[^>]*)>(.*?)</a>", in: block).first
        let anchorAttrs = anchor?[1] ?? ""
        let anchorText = anchor?[2] ?? ""

        var id: Int?
        if let s = capture("No\\.(\\d+)", in: anchorText) { id = Int(s) }
        if id == nil, let s = capture("data-threads-id=\"(\\d+)\"", in: block) { id = Int(s) }
        guard let postId = id else { return nil }

        // 主串号只认 href 里明确的 /t/xxx。回复的引用链接是 ?r=xxx&page=N 形式，
        // 不含主串号，这时留空，由界面层决定怎么跳；页码倒是有，一并带上
        var mainPostId: Int? = kind == .reference ? nil : postId
        var refPage: Int?
        if let href = capture("href=\"([^\"]+)\"", in: anchorAttrs) {
            let cleaned = href.components(separatedBy: "?").first ?? href
            if let s = capture("/t/(\\d+)", in: cleaned) ?? capture("id/(\\d+)", in: cleaned), let n = Int(s) {
                mainPostId = n
            }
            refPage = capture("[?&]page=(\\d+)", in: href).flatMap(Int.init)
        }

        let title = capture("h-threads-info-title\"[^>]*>(.*?)</span>", in: block).map(plainText) ?? "无标题"
        let name = capture("h-threads-info-email\"[^>]*>(.*?)</span>", in: block).map(plainText) ?? "无名氏"
        let now = capture("h-threads-info-createdat\"[^>]*>(.*?)</span>", in: block).map(plainText) ?? ""
        let uidRaw = capture("h-threads-info-uid\"[^>]*>(.*?)</span>", in: block).map(plainText) ?? ""
        let userHash = uidRaw.hasPrefix("ID:") ? String(uidRaw.dropFirst(3)) : uidRaw
        let isAdmin = block.contains("h-threads-info-uid") && block.contains("<font color=\"#FF0000\">")
        let content = capture("h-threads-content\"[^>]*>(.*?)</div>", in: block) ?? ""

        var img = "", ext = ""
        let imgTag = capture("(<a[^>]*h-threads-img-a[^>]*>)", in: block) ?? block
        let file = capture("href=\"[^\"]*/image/([^\"]+)\"", in: imgTag)
            ?? capture("<img[^>]*src=\"[^\"]*/thumb/([^\"]+)\"", in: block)
        if let file, let dot = file.lastIndex(of: ".") {
            img = String(file[file.startIndex..<dot])
            ext = String(file[dot...])
        }

        var replyCount: Int?
        if let s = capture("回应有 (\\d+) 篇被省略", in: block) { replyCount = Int(s) }

        return XDPost(id: postId,
                      replyCount: replyCount,
                      image: img,
                      imageExtension: ext,
                      postTime: XDTime.parseServer(now),
                      userHash: userHash,
                      name: name.isEmpty ? "无名氏" : name,
                      title: title.isEmpty ? "无标题" : title,
                      content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                      isAdmin: isAdmin,
                      kind: kind,
                      mainPostId: mainPostId,
                      refPage: refPage)
    }

    static func parseCookieExport(_ html: String, id: Int) -> XDCookie? {
        guard let src = capture("tpl-form-maintext(?:.*?)<img[^>]*src=\"([^\"]+)\"", in: html) else { return nil }
        let decoded = decodeEntities(src)
        guard decoded.contains("text="), var cookie = CookieStore.parse(decoded) else { return nil }
        cookie.remoteId = id
        return cookie
    }

    static func parseCookiesList(_ html: String) -> CookiesListInfo? {
        var canGet = false
        if let t = capture("am-text-success\"[^>]*>(.*?)</b>", in: html), t.contains("已开放") {
            canGet = true
        }
        let text = plainText(html)
        guard let numMatch = firstMatch("(\\d+)\\s*/\\s*(\\d+)", in: text),
              let cur = numMatch[1].flatMap({ Int($0) }),
              let total = numMatch[2].flatMap({ Int($0) }) else { return nil }
        let ids = matches("Cookie/export/id/(\\d+)", in: html).compactMap { $0[1].flatMap { Int($0) } }
        return CookiesListInfo(canGetCookie: canGet, current: cur, total: total, ids: Array(Set(ids)).sorted())
    }
}
