import Foundation

protocol ForumLike: Identifiable {
    var id: Int { get }
    var name: String { get }
    var displayName: String { get }
    var message: String { get }
    var maxPage: Int { get }
}

extension ForumLike {
    var showName: String {
        let raw = displayName.isEmpty ? name : displayName
        guard raw.contains("<") || raw.contains("&") else { return raw }
        return XDContent.plainText(raw)
    }
}

struct Timeline: ForumLike, Codable, Hashable {
    var id: Int
    var name: String
    var displayName: String
    var message: String
    var maxPage: Int

    init(id: Int, name: String, displayName: String = "", message: String = "", maxPage: Int = 20) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.message = message
        self.maxPage = maxPage
    }

    init(json: [String: Any]) {
        id = XDJSON.int(json["id"]) ?? 0
        name = json["name"] as? String ?? "未知时间线"
        displayName = json["display_name"] as? String ?? ""
        message = json["notice"] as? String ?? ""
        maxPage = XDJSON.int(json["max_page"]) ?? 20
    }
}

struct ForumGroup: Codable, Hashable, Identifiable {
    var id: Int
    var sort: Int
    var name: String

    init(json: [String: Any]) {
        id = XDJSON.int(json["id"]) ?? 0
        sort = XDJSON.int(json["sort"]) ?? 1
        name = json["name"] as? String ?? "未知版块组"
    }
}

struct Forum: ForumLike, Codable, Hashable {
    var id: Int
    var groupId: Int
    var sort: Int
    var name: String
    var displayName: String
    var message: String
    var interval: Int
    var threadCount: Int
    var permissionLevel: Int

    var maxPage: Int { threadCount > 0 ? min(Int(ceil(Double(threadCount) / 20.0)), 100) : 1 }

    init(json: [String: Any]) {
        id = XDJSON.int(json["id"]) ?? 0
        groupId = XDJSON.int(json["fgroup"]) ?? 4
        sort = XDJSON.int(json["sort"]) ?? 1
        name = json["name"] as? String ?? "未知版块"
        displayName = json["showName"] as? String ?? ""
        message = json["msg"] as? String ?? ""
        interval = XDJSON.int(json["interval"]) ?? 30
        threadCount = XDJSON.int(json["thread_count"]) ?? 0
        permissionLevel = XDJSON.int(json["permission_level"]) ?? 0
    }
}

struct ForumListResult {
    var groups: [ForumGroup]
    var forums: [Forum]
    var timelines: [Timeline]
}

enum PostKind: String, Codable {
    case post, tip, reference, feed
}

struct XDPost: Identifiable, Codable, Hashable {
    var id: Int
    var forumId: Int?
    var replyCount: Int?
    var image: String
    var imageExtension: String
    var postTime: Date
    var userHash: String
    var name: String
    var title: String
    var content: String
    var isSage: Bool
    var isAdmin: Bool
    var isHidden: Bool
    var kind: PostKind
    var mainPostId: Int?

    var hasImage: Bool { !image.isEmpty }
    var imageFile: String? { hasImage ? image + imageExtension : nil }
    var preview: String { String(XDContent.previewText(content).prefix(120)) }
    var maxPage: Int {
        guard let c = replyCount else { return 1 }
        return c > 0 ? Int(ceil(Double(c) / 19.0)) : 1
    }

    init(id: Int,
         forumId: Int? = nil,
         replyCount: Int? = nil,
         image: String = "",
         imageExtension: String = "",
         postTime: Date = .distantPast,
         userHash: String = "",
         name: String = "无名氏",
         title: String = "无标题",
         content: String = "",
         isSage: Bool = false,
         isAdmin: Bool = false,
         isHidden: Bool = false,
         kind: PostKind = .post,
         mainPostId: Int? = nil) {
        self.id = id
        self.forumId = forumId
        self.replyCount = replyCount
        self.image = image
        self.imageExtension = imageExtension
        self.postTime = postTime
        self.userHash = userHash
        self.name = name
        self.title = title
        self.content = content
        self.isSage = isSage
        self.isAdmin = isAdmin
        self.isHidden = isHidden
        self.kind = kind
        self.mainPostId = mainPostId
    }

    init(json: [String: Any], kind: PostKind = .post) {
        id = XDJSON.int(json["id"]) ?? 0
        forumId = XDJSON.int(json["fid"])
        replyCount = XDJSON.int(json["ReplyCount"]) ?? XDJSON.int(json["replyCount"]) ?? XDJSON.int(json["reply_count"])
        image = json["img"] as? String ?? ""
        imageExtension = json["ext"] as? String ?? ""
        postTime = XDTime.parseServer(json["now"] as? String ?? "")
        userHash = json["user_hash"] as? String ?? json["userid"] as? String ?? ""
        name = (json["name"] as? String).map(XDContent.unescape).flatMap { $0.isEmpty ? nil : $0 } ?? "无名氏"
        title = (json["title"] as? String).map(XDContent.unescape).flatMap { $0.isEmpty ? nil : $0 } ?? "无标题"
        content = json["content"] as? String ?? ""
        isSage = (XDJSON.int(json["sage"]) ?? 0) != 0
        isAdmin = (XDJSON.int(json["admin"]) ?? 0) != 0
        isHidden = (XDJSON.int(json["Hide"]) ?? XDJSON.int(json["hide"]) ?? 0) != 0
        self.kind = kind
        mainPostId = XDJSON.int(json["resto"]) ?? XDJSON.int(json["parent_id"])
    }
}

struct ForumThread: Identifiable, Hashable {
    var id: Int { mainPost.id }
    var mainPost: XDPost
    var recentReplies: [XDPost]
    var remainReplies: Int?

    var lastReplyTime: Date {
        recentReplies.max(by: { $0.postTime < $1.postTime })?.postTime ?? mainPost.postTime
    }
}

struct ThreadPage {
    var mainPost: XDPost
    var replies: [XDPost]
    var tip: XDPost?
    var maxPage: Int { mainPost.maxPage }
}

struct XDCookie: Codable, Hashable, Identifiable {
    var id: String { userHash }
    var userHash: String
    var name: String
    var remoteId: Int?
    var displayIds: [String]?

    var cookieValue: String { "userhash=\(userHash)" }
}

struct CookiesListInfo {
    var canGetCookie: Bool
    var current: Int
    var total: Int
    var ids: [Int]
}

struct XDImagePayload {
    var data: Data
    var filename: String
    var mime: String
}

enum XDJSON {
    static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        if let b = any as? Bool { return b ? 1 : 0 }
        return nil
    }

    static func object(_ data: Data) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw XDError.decode(error.localizedDescription) }
    }

    static func checkError(_ decoded: Any) throws {
        if let s = decoded as? String { throw XDError.api(s) }
        if let m = decoded as? [String: Any], let e = m["error"] { throw XDError.api("\(e)") }
    }
}

enum XDTime {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        f.dateFormat = format
        return f
    }

    private static let isoLike = formatter("yyyy-MM-dd'T'HH:mm:ss")
    private static let plain = formatter("yyyy-MM-dd HH:mm:ss")
    private static let weekdayRegex = try! NSRegularExpression(pattern: "\\([^)]*\\)", options: [])

    static func parseServer(_ raw: String) -> Date {
        guard !raw.isEmpty else { return .distantPast }
        let ns = raw as NSString
        let s = weekdayRegex.stringByReplacingMatches(
            in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "T")
        if let d = isoLike.date(from: s) { return d }
        return plain.date(from: raw) ?? .distantPast
    }
}
