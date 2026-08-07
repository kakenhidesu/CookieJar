import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var items: [XDPost] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var reachedEnd = false
    private var page = 1
    private var ids = Set<Int>()
    private var inflight: Task<Void, Never>?

    func refresh() async {
        await inflight?.value
        page = 1
        reachedEnd = false
        await load(reset: true)
    }

    func loadMoreIfNeeded(current post: XDPost) async {
        guard !isLoading, !reachedEnd, items.last?.id == post.id else { return }
        page += 1
        await load(reset: false)
    }

    func load(reset: Bool) async {
        guard !isLoading else { return }
        let task = Task { @MainActor in await self.performLoad(reset: reset) }
        inflight = task
        await task.value
        inflight = nil
    }

    private func performLoad(reset: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await FeedService.shared.feed(page: page)
            if reset { items = []; ids = [] }
            let blacklist = BlacklistStore.shared
            let fresh = result.filter { !ids.contains($0.id) && !blacklist.shouldHide($0) }
            fresh.forEach { ids.insert($0.id) }
            items.append(contentsOf: fresh)
            reachedEnd = result.isEmpty
            error = nil
        } catch {
            self.error = error.localizedDescription
            if page > 1 { page -= 1 }
        }
    }

    func unsubscribe(_ post: XDPost) async {
        do {
            try await FeedService.shared.unsubscribe(mainPostId: post.id)
            items.removeAll { $0.id == post.id }
            ids.remove(post.id)
            Toast.shared.success("已取消订阅")
        } catch {
            Toast.shared.error(error)
        }
    }
}

struct FeedScreen: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var vm = FeedViewModel()
    @State private var query = ""

    private var visibleItems: [XDPost] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = q.isEmpty ? vm.items : vm.items.filter { post in
            post.title.localizedCaseInsensitiveContains(q)
                || post.name.localizedCaseInsensitiveContains(q)
                || post.userHash.localizedCaseInsensitiveContains(q)
                || "\(post.id)".contains(q)
                || XDContent.plainText(post.content).localizedCaseInsensitiveContains(q)
        }
        return settings.feedSort.apply(to: matched)
    }

    var body: some View {
        ZStack {
            XDTheme.background.ignoresSafeArea()
            feedList
        }
        .navigationTitle("订阅")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索关键字（标题 / 正文 / 饼干 / 串号）")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("排序", selection: $settings.feedSortRaw) {
                        ForEach(FeedSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.icon).tag(sort.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                Button {
                    Task { await vm.refresh() }
                } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { if vm.items.isEmpty { await vm.load(reset: true) } }
        .onChange(of: app.refreshTick[.feed] ?? 0) { _ in
            Task { await vm.refresh() }
        }
    }

    private var feedList: some View {
        let items = visibleItems
        return ScrollView {
            LazyVStack(spacing: XDTheme.cardSpacing) {
                ForEach(items) { post in
                    Button {
                        app.openThread(post.id)
                    } label: {
                        PostBodyView(post: post, isPo: true, lineLimit: 6, showForum: true, showReplyCount: true,
                                     onTapImage: { url in
                                         app.imageViewer = ImageViewerPayload(images: [url], index: 0)
                                     })
                            .xdCard()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await vm.unsubscribe(post) }
                        } label: { Label("取消订阅", systemImage: "bookmark.slash") }
                    }
                    .task { await vm.loadMoreIfNeeded(current: post) }
                }

                if !query.isEmpty && items.isEmpty && !vm.items.isEmpty {
                    EmptyStateView(icon: "magnifyingglass",
                                   title: "没有匹配的订阅",
                                   subtitle: "只在已加载的订阅里搜索，往下多翻几页再试。")
                } else {
                    ListStatusView(isLoading: vm.isLoading,
                                   error: vm.error,
                                   isEmpty: vm.items.isEmpty,
                                   emptyIcon: "bookmark",
                                   emptyTitle: "还没有订阅",
                                   emptySubtitle: "在串页面点右上角书签即可订阅。\n订阅 ID 可在「我的 → 设置 → 订阅」中查看和同步。",
                                   retry: { Task { await vm.refresh() } })
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .refreshable { await vm.refresh() }
    }
}
