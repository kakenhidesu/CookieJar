import Foundation

enum ReplyHistoryReconciler {
    @discardableResult
    static func merge(_ observed: [PostRecord], into records: inout [PostRecord],
                      cookieHashesForDisplayId: (String) -> Set<String>) -> Bool {
        let before = records
        var byPostId: [Int: PostRecord] = [:]
        for record in records + observed where record.kind == .reply && record.status == .accepted {
            if let id = record.postId, id > 0 { byPostId[id] = record }
        }
        let replies = byPostId.values.sorted { ($0.postId ?? 0) < ($1.postId ?? 0) }
        var candidates: [Int: [UUID]] = [:]
        var uses: [UUID: Int] = [:]
        for reply in replies {
            guard let postId = reply.postId else { continue }
            let hashes = cookieHashesForDisplayId(reply.userHash)
            let matchingIds = records.filter { matches($0, reply: reply, cookieHashes: hashes) }.map(\.id)
            candidates[postId] = matchingIds
            for id in matchingIds { uses[id, default: 0] += 1 }
        }

        for reply in replies {
            guard let postId = reply.postId else { continue }
            // Require a unique match in both directions; repeated identical replies remain unlinked.
            if let matches = candidates[postId], matches.count == 1,
               let localId = matches.first, uses[localId] == 1,
               let index = records.firstIndex(where: { $0.id == localId }) {
                records[index].postId = postId
                records[index].status = .accepted
                records[index].forumId = records[index].forumId ?? reply.forumId
                records.removeAll { $0.id != localId && $0.status == .accepted && $0.postId == postId }
            } else if !records.contains(where: { $0.status == .accepted && $0.postId == postId }) {
                records.append(reply)
            }
        }
        return before != records
    }

    private static func matches(_ local: PostRecord, reply: PostRecord, cookieHashes: Set<String>) -> Bool {
        guard local.kind == .reply, local.postId == nil,
              local.status == .accepted || local.status == .resultUnknown,
              local.mainPostId == reply.mainPostId,
              cookieHashes.contains(local.userHash),
              local.createdAt != .distantPast, reply.createdAt != .distantPast else { return false }
        let elapsed = reply.createdAt.timeIntervalSince(local.createdAt)
        // Server timestamps have second precision; allow a small clock difference and a slow upload.
        guard elapsed >= -5 && elapsed <= 180 else { return false }
        return local.hasImage == reply.hasImage
            && normalize(local.content) == normalize(reply.content)
            && normalizeTitle(local.title) == normalizeTitle(reply.title)
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[h]", with: "")
            .replacingOccurrences(of: "[/h]", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeTitle(_ title: String) -> String {
        let value = normalize(title)
        return value == "无标题" ? "" : value
    }
}
