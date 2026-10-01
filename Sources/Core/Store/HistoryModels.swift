import Foundation

struct BrowseRecord: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var preview: String
    var userHash: String
    var forumId: Int?
    var replyCount: Int?
    var image: String
    var imageExtension: String
    var lastPage: Int
    var lastPostId: Int?
    var browsedAt: Date
}

struct PostRecord: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case thread, reply }
    enum SendStatus: String, Codable { case accepted, resultUnknown, legacy }

    var id: UUID
    var postId: Int?
    var status: SendStatus
    var kind: Kind
    var mainPostId: Int?
    var forumId: Int?
    var title: String
    var content: String
    var userHash: String
    var hasImage: Bool
    var createdAt: Date

    init(id: UUID = UUID(), postId: Int? = nil, status: SendStatus, kind: Kind,
         mainPostId: Int?, forumId: Int?, title: String, content: String,
         userHash: String, hasImage: Bool, createdAt: Date) {
        self.id = id
        self.postId = postId
        self.status = status
        self.kind = kind
        self.mainPostId = mainPostId
        self.forumId = forumId
        self.title = title
        self.content = content
        self.userHash = userHash
        self.hasImage = hasImage
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id = "localId", postId, status, kind, mainPostId, forumId, title, content, userHash, hasImage, createdAt
    }

    private enum LegacyKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        mainPostId = try c.decodeIfPresent(Int.self, forKey: .mainPostId)
        forumId = try c.decodeIfPresent(Int.self, forKey: .forumId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        userHash = try c.decodeIfPresent(String.self, forKey: .userHash) ?? ""
        hasImage = try c.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if let localId = try c.decodeIfPresent(UUID.self, forKey: .id) {
            id = localId
            postId = try c.decodeIfPresent(Int.self, forKey: .postId)
            status = (try? c.decodeIfPresent(SendStatus.self, forKey: .status)) ?? .legacy
        } else {
            let legacyId = (try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Int.self, forKey: .id)) ?? 0
            id = UUID()
            postId = legacyId > 0 ? legacyId : nil
            status = .legacy
        }
    }
}

struct LastReadSession: Codable, Hashable {
    var mainPostId: Int
    var page: Int
    var postId: Int?
    var onlyPo: Bool
    var savedAt: Date
}

struct ThreadReadProgress: Codable, Hashable {
    var page: Int
    var postId: Int?
    var updatedAt: Date
}
