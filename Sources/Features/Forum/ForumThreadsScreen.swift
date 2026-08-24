import SwiftUI

@MainActor
final class ThreadListViewModel: ObservableObject {
    @Published var items: [ForumThread] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var showRefreshBanner = false
    @Published var error: String?
    @Published var reachedEnd = false

    private(set) var page = 1
    var forumId: Int = -1
    var isTimeline: Bool = true
    private var loadedIds = Set<Int>()
    private var inflight: Task<Void, Never>?

    var maxPage: Int {
        if isTimeline { return ForumStore.shared.timeline(id: forumId)?.maxPage ?? 20 }
        return ForumStore.shared.forum(id: forumId)?.maxPage ?? 100
    }

    func configure(forumId: Int, isTimeline: Bool) async {
        guard self.forumId != forumId || self.isTimeline != isTimeline || items.isEmpty else { return }
        self.forumId = forumId
        self.isTimeline = isTimeline
        items = []
        loadedIds = []
        page = 1
        reachedEnd = false
        await load(reset: true)
    }

    func refresh(showBanner: Bool = false) async {
        await inflight?.value
        isRefreshing = true
        showRefreshBanner = showBanner
        page = 1
        reachedEnd = false
        await load(reset: true)
        isRefreshing = false
        showRefreshBanner = false
    }

    func loadMoreIfNeeded(current item: ForumThread) async {
        guard !isLoading, !reachedEnd, items.last?.id == item.id else { return }
        page += 1
        await load(reset: false)
    }

    func retry() async {
        await inflight?.value
        if items.isEmpty {
            page = 1
            reachedEnd = false
            await load(reset: true)
        } else {
            page += 1
            await load(reset: false)
        }
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
        LaunchLog.mark("列表请求 id=\(forumId) timeline=\(isTimeline) page=\(page)")
        do {
            let cookie = CookieStore.shared.cookieValue
            let result: [ForumThread]
            if isTimeline {
                result = try await XDAPI.shared.timelineThreads(timelineId: forumId, page: page, cookie: cookie)
            } else {
                result = try await XDAPI.shared.forumThreads(forumId: forumId, page: page, cookie: cookie)
            }
            if reset {
                items = []
                loadedIds = []
            }
            let blacklist = BlacklistStore.shared
            let fresh = result
                .filter { !loadedIds.contains($0.id) && !blacklist.shouldHide($0.mainPost) }
                .map { item -> ForumThread in
                    var item = item
                    item.recentReplies = item.recentReplies.filter { !blacklist.shouldHide($0) }
                    return item
                }
            fresh.forEach { loadedIds.insert($0.id) }
            items.append(contentsOf: fresh)
            reachedEnd = result.isEmpty || page >= maxPage
            error = nil
            LaunchLog.mark("列表完成 \(fresh.count) 条")
        } catch {
            self.error = error.localizedDescription
            if page > 1 { page -= 1 }
            LaunchLog.mark("列表失败 \(error.localizedDescription)")
        }
    }
}

struct ForumThreadsScreen: View {
    var forumId: Int?
    var isTimeline: Bool = true

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var forums: ForumStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var vm = ThreadListViewModel()
    @State private var showForumPicker = false
    @State private var showForumInfo = false

    private var effectiveForumId: Int { forumId ?? app.currentForumId }
    private var effectiveIsTimeline: Bool { forumId == nil ? app.currentIsTimeline : isTimeline }
    private var isRoot: Bool { forumId == nil }

    private var title: String {
        forums.name(forId: effectiveForumId, isTimeline: effectiveIsTimeline)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            XDTheme.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: XDTheme.cardSpacing) {
                        if vm.showRefreshBanner {
                            InlineLoading(text: "正在刷新…")
                        }

                        ForEach(vm.items) { item in
                            Button {
                                app.openThread(item.mainPost.id)
                            } label: {
                                ThreadCardView(item: item, showForum: effectiveIsTimeline)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { contextMenu(for: item) }
                            .task { await vm.loadMoreIfNeeded(current: item) }
                        }

                        ListStatusView(isLoading: vm.isLoading && !vm.isRefreshing,
                                       error: vm.error,
                                       isEmpty: vm.items.isEmpty,
                                       reachedEnd: vm.reachedEnd,
                                       retry: { Task { await vm.retry() } },
                                       refresh: { Task { await vm.refresh(showBanner: true) } })
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .id("top")
                }
                .refreshable { await vm.refresh() }
                .onChange(of: app.refreshTick[.forums] ?? 0) { _ in
                    guard isRoot else { return }
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                    Haptics.light()
                    Task { await vm.refresh(showBanner: true) }
                }
            }

            composeButton
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showForumPicker = true
                        Haptics.light()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showForumInfo = true
                    } label: { Label("版块说明", systemImage: "info.circle") }
                    Button {
                        Task { await vm.refresh(showBanner: true) }
                    } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    Button {
                        app.push(.searchResult(query: ""))
                    } label: { Label("搜索", systemImage: "magnifyingglass") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showForumPicker) {
            ForumPickerSheet { id, timeline in
                app.openForum(id: id, isTimeline: timeline)
                showForumPicker = false
            }
        }
        .sheet(isPresented: $showForumInfo) {
            ForumInfoSheet(forumId: effectiveForumId, isTimeline: effectiveIsTimeline)
                .presentationDetents([.medium])
        }
        .task(id: "\(effectiveForumId)-\(effectiveIsTimeline)") {
            await vm.configure(forumId: effectiveForumId, isTimeline: effectiveIsTimeline)
        }
    }

    private var composeButton: some View {
        XDFloatingButton(systemImage: "square.and.pencil") {
            guard CookieStore.shared.hasCookie else {
                Toast.shared.error("发串需要先添加饼干")
                return
            }
            app.compose = .newThread(forumId: effectiveIsTimeline ? nil : effectiveForumId)
            Haptics.medium()
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ForumThread) -> some View {
        Button {
            app.openThread(item.mainPost.id, onlyPo: true)
        } label: { Label("只看 Po", systemImage: "person.crop.circle") }

        Button {
            Task {
                do {
                    try await FeedService.shared.subscribe(mainPostId: item.mainPost.id)
                    Toast.shared.success("订阅成功")
                } catch {
                    Toast.shared.error(error)
                }
            }
        } label: { Label("订阅", systemImage: "bookmark") }

        postCommonMenuItems(item.mainPost)

        Button(role: .destructive) {
            BlacklistStore.shared.block(post: item.mainPost.id, title: item.mainPost.title)
            Toast.shared.show("已屏蔽该串")
        } label: { Label("屏蔽该串", systemImage: "eye.slash") }
    }
}

struct ForumInfoSheet: View {
    let forumId: Int
    let isTimeline: Bool
    @EnvironmentObject private var forums: ForumStore
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let message = isTimeline
                        ? (forums.timeline(id: forumId)?.message ?? "")
                        : (forums.forum(id: forumId)?.message ?? "")
                    XDRichText(paragraphs: XDContent.parse(message, revealHidden: true).paragraphs,
                               font: .system(size: 15))
                    if !isTimeline, let f = forums.forum(id: forumId) {
                        Divider()
                        LabeledContent("串数", value: "\(f.threadCount)")
                        LabeledContent("发串间隔", value: "\(f.interval) 秒")
                        if f.permissionLevel > 0 {
                            LabeledContent("权限", value: "需要饼干（等级 \(f.permissionLevel)）")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(XDTheme.background)
            .navigationTitle(forums.name(forId: forumId, isTimeline: isTimeline))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let id = XDContent.postId(fromRefURL: url) else { return .systemAction }
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                app.referencePostId = id
            }
            return .handled
        })
    }
}
