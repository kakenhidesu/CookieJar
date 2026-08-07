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

    private var directPostId: Int? {
        let digits = query.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
        guard digits.count >= 5, digits == query.trimmingCharacters(in: .whitespaces) else { return nil }
        return Int(digits)
    }

    var body: some View {
        ZStack {
            XDTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: XDTheme.cardSpacing) {
                    if let id = directPostId {
                        Button {
                            app.openThread(id)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.forward.app")
                                Text(verbatim: "直接打开 No.\(id)")
                                Spacer()
                            }
                            .font(.system(size: 15, weight: .medium))
                            .xdCard()
                        }
                        .buttonStyle(.plain)
                    }

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
                    } else if let error {
                        EmptyStateView(icon: "magnifyingglass",
                                       title: "搜索不可用",
                                       subtitle: "\(error)\n\nX 岛官方搜索接口时常关闭，可以用上面的「直接打开串号」功能。")
                    } else if searched && results.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "没有找到结果")
                    } else if !searched {
                        EmptyStateView(icon: "magnifyingglass",
                                       title: "搜索串内容",
                                       subtitle: "输入关键词搜索；输入纯数字可直接跳转到对应串号。")
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "关键词或串号")
        .onSubmit(of: .search) {
            page = 1
            Task { await search(reset: true) }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if query.isEmpty { query = initialQuery } }
    }

    private func search(reset: Bool) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
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
