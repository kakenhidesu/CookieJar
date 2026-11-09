import SwiftUI

struct SearchScreen: View {
    var initialQuery: String = ""

    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var results: [XDPost] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var page = 1
    @State private var searched = false

    private enum DirectTarget {
        case thread(id: Int, page: Int, onlyPo: Bool, replyId: Int?)
        case reference(Int)

        var title: String {
            switch self {
            case .thread(let id, _, _, _): return "直接打开 No.\(id)"
            case .reference(let id): return "查看引用 No.\(id)"
            }
        }

        static func parse(_ input: String) -> DirectTarget? {
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 5, let id = positiveNumber(text) {
                return .thread(id: id, page: 1, onlyPo: false, replyId: nil)
            }
            let isReference = text.hasPrefix(">>")
            let numbered = isReference
                ? String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces) : text
            if numbered.lowercased().hasPrefix("no."),
               let id = positiveNumber(String(numbered.dropFirst(3)).trimmingCharacters(in: .whitespaces)) {
                return isReference ? .reference(id) : .thread(id: id, page: 1, onlyPo: false, replyId: nil)
            }

            guard let url = URLComponents(string: text),
                  let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
                  let host = url.host?.lowercased(),
                  host.range(of: "^(www\\.)?nmbxd[0-9]*\\.com$", options: .regularExpression) != nil else { return nil }
            let parts = url.path.split(separator: "/").map { part in
                let value = String(part)
                return value.lowercased().hasSuffix(".html") ? String(value.dropLast(5)) : value
            }
            func parameter(_ name: String) -> String? {
                url.queryItems?.first(where: { $0.name == name })?.value
            }
            let replyId = positiveNumber(parameter("r"))
            if parts.count == 2, parts[0].lowercased() == "t", let id = positiveNumber(parts[1]) {
                return .thread(id: id, page: positiveNumber(parameter("page")) ?? 1,
                               onlyPo: false, replyId: replyId)
            }
            guard parts.count >= 2, parts[0].lowercased() == "forum",
                  ["thread", "po"].contains(parts[1].lowercased()), parts.count.isMultiple(of: 2) else { return nil }
            var pathParameters: [String: String] = [:]
            for index in stride(from: 2, to: parts.count, by: 2) {
                pathParameters[parts[index].lowercased()] = parts[index + 1]
            }
            guard let id = positiveNumber(pathParameters["id"] ?? parameter("id")) else { return nil }
            return .thread(id: id, page: positiveNumber(pathParameters["page"] ?? parameter("page")) ?? 1,
                           onlyPo: parts[1].lowercased() == "po", replyId: replyId)
        }

        private static func positiveNumber(_ value: String?) -> Int? {
            guard let value, !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(value), number > 0 else { return nil }
            return number
        }
    }

    private var directTarget: DirectTarget? { DirectTarget.parse(query) }

    private func open(_ target: DirectTarget) {
        switch target {
        case .thread(let id, let page, let onlyPo, let replyId):
            app.openThread(id, page: page, onlyPo: onlyPo, jumpTo: replyId)
        case .reference(let id):
            app.referencePostId = id
        }
    }

    var body: some View {
        ZStack {
            XDTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: XDTheme.cardSpacing) {
                    if let target = directTarget {
                        Button {
                            open(target)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.forward.app")
                                Text(verbatim: target.title)
                                Spacer()
                            }
                            .font(.system(size: 15, weight: .medium))
                            .xdCard()
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(results) { post in
                            Button {
                                app.openThread(post.mainPostId ?? post.id, jumpTo: post.id)
                            } label: {
                                PostBodyView(post: post, lineLimit: 6, showForum: true)
                                    .xdCard()
                            }
                            .buttonStyle(.plain)
                        }

                        if isLoading {
                            InlineLoading(text: "搜索中…")
                        } else if error != nil {
                            EmptyStateView(icon: "magnifyingglass",
                                           title: "搜索不可用",
                                           subtitle: "x岛官方搜索接口已关闭，我们有生之年再见( ´_ゝ`)旦\n您仍可以使用直接跳转串号的功能")
                        } else if searched && results.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "没有找到结果")
                        } else if !searched {
                            EmptyStateView(icon: "magnifyingglass",
                                           title: "搜索串内容",
                                           subtitle: "输入关键词搜索；粘贴串号、No.、>>No. 或完整串链接可直接打开。")
                        }

                        if !results.isEmpty && !isLoading {
                            Button("加载更多") {
                                page += 1
                                Task { await search(reset: false) }
                            }
                            .buttonStyle(.bordered)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "关键词、串号或链接")
        .onSubmit(of: .search) {
            if let target = directTarget {
                open(target)
                return
            }
            page = 1
            Task { await search(reset: true) }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if query.isEmpty { query = initialQuery } }
    }

    private func search(reset: Bool) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, DirectTarget.parse(q) == nil else { return }
        isLoading = true
        searched = true
        defer { isLoading = false }
        do {
            let list = try await XDAPI.shared.search(query: q, page: page, cookie: CookieStore.shared.cookieValue)
            if reset { results = [] }
            let existing = Set(results.map(\.id))
            results.append(contentsOf: list.filter { !existing.contains($0.id) })
            error = nil
        } catch {
            if reset { results = [] }
            self.error = error.localizedDescription
        }
    }
}
