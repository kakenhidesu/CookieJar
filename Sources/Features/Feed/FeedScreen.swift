import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    static let shared = FeedViewModel()

    @Published var items: [XDPost] = []
    @Published var isLoading = false
    @Published var error: String?
    private var context = ""
    private var requestID = UUID()
    private var inflight: Task<Void, Never>?
    @Published private(set) var isRestoring = false
    @Published private(set) var isBatchUpdating = false

    func refreshIfNeeded() async {
        guard context != SettingsStore.shared.feedContextID else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRestoring, !isBatchUpdating else { return }
        let selectedContext = SettingsStore.shared.feedContextID
        if context == selectedContext, let inflight {
            await inflight.value
            return
        }
        inflight?.cancel()
        if context != selectedContext { items = [] }
        context = selectedContext
        FeedUnreadStore.shared.configure(context: selectedContext)
        FeedUnreadStore.shared.beginRefresh()
        let request = UUID()
        requestID = request
        isLoading = true
        error = nil
        let task = Task { @MainActor in
            await self.performRefresh(context: selectedContext, request: request)
        }
        inflight = task
        await task.value
        if requestID == request { inflight = nil }
    }

    private func performRefresh(context: String, request: UUID) async {
        defer { if requestID == request { isLoading = false } }
        var page = 1
        var seen = Set<Int>()
        var visibleIDs = Set<Int>()
        do {
            while true {
                let result = try await FeedService.shared.feed(page: page)
                guard requestID == request, context == SettingsStore.shared.feedContextID,
                      !Task.isCancelled else { return }
                if page == 1 { items = [] }
                let newPosts = result.filter { !seen.contains($0.id) }
                seen.formUnion(result.map(\.id))
                let fresh = newPosts.filter { !BlacklistStore.shared.shouldHide($0) }
                let freshIDs = fresh.map(\.id)
                items.append(contentsOf: fresh)
                visibleIDs.formUnion(freshIDs)
                FeedUnreadStore.shared.track(freshIDs)
                FeedReplyCountStore.shared.request(freshIDs,
                    cookie: CookieStore.shared.cookieValue, force: true)
                // Some endpoints repeat their final page instead of returning an empty one.
                if result.isEmpty || newPosts.isEmpty { break }
                page += 1
            }
            FeedUnreadStore.shared.reconcile(visibleIDs)
            await FeedReplyCountStore.shared.waitUntilFinished()
        } catch {
            guard requestID == request, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func retry() async { await refresh() }

    func beginRestore() {
        isRestoring = true
        requestID = UUID()
        inflight?.cancel()
        inflight = nil
        isLoading = false
        FeedReplyCountStore.shared.cancelPending()
    }

    func finishRestore() {
        isRestoring = false
        context = ""
        items = []
        Task { await refresh() }
    }

    func unsubscribe(_ post: XDPost) async {
        do {
            try await FeedService.shared.unsubscribe(mainPostId: post.id)
            items.removeAll { $0.id == post.id }
            Toast.shared.success("已取消订阅")
        } catch {
            Toast.shared.error(error)
        }
    }

    func unsubscribe(_ ids: Set<Int>) async -> Set<Int> {
        guard !ids.isEmpty, !isBatchUpdating, !isLoading, !isRestoring else { return ids }
        guard CookieStore.shared.hasCookie else {
            Toast.shared.error(XDError.needCookie)
            return ids
        }
        let context = SettingsStore.shared.feedContextID
        let generation = HistoryStore.shared.restoreGeneration
        isBatchUpdating = true
        defer {
            isBatchUpdating = false
            if !isCurrentFeed(context: context, generation: generation) {
                Task { await refresh() }
            }
        }
        var remaining = ids
        for id in ids.sorted() {
            guard !Task.isCancelled, !isRestoring,
                  isCurrentFeed(context: context, generation: generation) else { break }
            do {
                try await FeedService.shared.unsubscribe(mainPostId: id, expectedContext: context)
                remaining.remove(id)
                if isCurrentFeed(context: context, generation: generation) {
                    items.removeAll { $0.id == id }
                }
            } catch { continue }
        }
        if isCurrentFeed(context: context, generation: generation) {
            if remaining.isEmpty {
                Toast.shared.success("已取消 \(ids.count) 个订阅")
            } else {
                Toast.shared.show("已取消 \(ids.count - remaining.count) 个，\(remaining.count) 个未完成")
            }
        }
        return remaining
    }

    private func isCurrentFeed(context: String, generation: UUID) -> Bool {
        SettingsStore.shared.feedContextID == context && HistoryStore.shared.restoreGeneration == generation
    }
}

struct FeedScreen: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var vm = FeedViewModel.shared
    @ObservedObject private var unread = FeedUnreadStore.shared
    @ObservedObject private var replyCounts = FeedReplyCountStore.shared
    @ObservedObject private var library = FeedLibraryStore.shared
    @State private var query = ""
    @State private var selectedGroup = "all"
    @State private var showGroups = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var showBatchUnsubscribe = false

    private var visibleItems: [XDPost] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let counted = vm.items.map { post -> XDPost in
            var post = post
            post.replyCount = replyCounts.entries[post.id]?.count
            return post
        }
        let matched = q.isEmpty ? counted : counted.filter { post in
            post.title.localizedCaseInsensitiveContains(q)
                || post.name.localizedCaseInsensitiveContains(q)
                || post.userHash.localizedCaseInsensitiveContains(q)
                || "\(post.id)".contains(q)
                || XDContent.plainText(post.content).localizedCaseInsensitiveContains(q)
        }
        let collection = library.current
        let filtered = matched.filter { post in
            if settings.feedOnlyUpdated && unread.unreadCount(for: post.id) == 0 { return false }
            if selectedGroup == "ungrouped" { return collection.assignments[post.id] == nil }
            if selectedGroup != "all" {
                return collection.assignments[post.id]?.uuidString == selectedGroup
            }
            return true
        }
        return settings.feedSort.apply(to: filtered).enumerated().sorted { a, b in
            let aPinned = collection.pinned.contains(a.element.id)
            let bPinned = collection.pinned.contains(b.element.id)
            if aPinned != bPinned { return aPinned }
            if settings.feedUpdatedFirst {
                let aUnread = unread.unreadCount(for: a.element.id) > 0
                let bUnread = unread.unreadCount(for: b.element.id) > 0
                if aUnread != bUnread { return aUnread }
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    var body: some View {
        ZStack {
            XDTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                filterBar
                feedList
            }
        }
        .navigationTitle("订阅")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索关键字（标题 / 正文 / 饼干 / 串号）")
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting { selectionBar }
        }
        .onChange(of: app.refreshTick[.feed] ?? 0) { _ in
            Task { await vm.refresh() }
        }
        .sheet(isPresented: $showGroups) { FeedGroupsScreen() }
        .onChange(of: library.current.groups.map(\.id)) { ids in
            if let id = UUID(uuidString: selectedGroup), !ids.contains(id) { selectedGroup = "all" }
        }
        .onChange(of: settings.feedContextID) { _ in
            selectedGroup = "all"
            selectedIDs = []
            isSelecting = false
        }
        .onChange(of: visibleItems.map(\.id)) { ids in
            selectedIDs.formIntersection(Set(ids))
        }
        .confirmationDialog("取消选中的 \(selectedIDs.count) 个订阅？", isPresented: $showBatchUnsubscribe,
                            titleVisibility: .visible) {
            Button("取消订阅", role: .destructive) {
                let ids = selectedIDs
                let context = settings.feedContextID
                let generation = HistoryStore.shared.restoreGeneration
                Task {
                    let remaining = await vm.unsubscribe(ids)
                    guard context == settings.feedContextID,
                          generation == HistoryStore.shared.restoreGeneration else { return }
                    selectedIDs = remaining.intersection(Set(visibleItems.map(\.id)))
                    if selectedIDs.isEmpty { isSelecting = false }
                }
            }
            Button("保留订阅", role: .cancel) {}
        }
    }

    private var filterBar: some View {
        HStack {
            Menu {
                Picker("分组", selection: $selectedGroup) {
                    Text("全部订阅").tag("all")
                    Text("未分组").tag("ungrouped")
                    ForEach(library.current.groups) { Text($0.name).tag($0.id.uuidString) }
                }
                Button("管理分组") { showGroups = true }
            } label: {
                Label(groupName, systemImage: "folder")
            }
            Spacer()
            Toggle("仅看更新", isOn: $settings.feedOnlyUpdated)
                .toggleStyle(.button)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .disabled(vm.isBatchUpdating)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button(isSelecting ? "完成" : "多选") {
                isSelecting.toggle()
                selectedIDs = []
            }
            .disabled(vm.isBatchUpdating)
            Menu {
                Toggle("有更新优先", isOn: $settings.feedUpdatedFirst)
                Picker("排序", selection: $settings.feedSortRaw) {
                    ForEach(FeedSort.allCases) { sort in
                        Label(sort.label, systemImage: sort.icon).tag(sort.rawValue)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .disabled(vm.isBatchUpdating)
            Button {
                Task { await vm.refresh() }
            } label: { Image(systemName: "arrow.clockwise") }
            .disabled(vm.isBatchUpdating)
        }
    }

    private func feedRow(_ post: XDPost) -> some View {
        Button {
            if isSelecting {
                if !selectedIDs.insert(post.id).inserted { selectedIDs.remove(post.id) }
            } else {
                app.openThread(post.id)
            }
        } label: {
            feedCard(post)
        }
        .buttonStyle(.plain)
        .disabled(vm.isBatchUpdating)
        .contextMenu {
            if !isSelecting {
                feedMenu(post)
            }
        }
    }

    private func feedCard(_ post: XDPost) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if isSelecting {
                Image(systemName: selectedIDs.contains(post.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(settings.accent.color)
                    .accessibilityLabel(selectedIDs.contains(post.id) ? "已选择" : "未选择")
            }
            VStack(alignment: .leading, spacing: 10) {
                if library.current.pinned.contains(post.id) {
                    Label("置顶", systemImage: "pin.fill")
                        .font(.caption).foregroundStyle(settings.accent.color)
                }
                PostBodyView(post: post, isPo: true, lineLimit: 6, showForum: true,
                             showPostId: false,
                             onTapImage: { url in
                                 app.imageViewer = ImageViewerPayload(images: [url], index: 0)
                             })
                    .allowsHitTesting(!isSelecting)

                HStack(spacing: 10) {
                    replyCountLabel(for: post)
                        .allowsHitTesting(!isSelecting)
                    Spacer()
                    Text(verbatim: "No.\(post.id)")
                        .font(.system(size: settings.captionFontSize, design: .monospaced))
                        .foregroundStyle(XDTheme.secondaryText.opacity(0.8))
                }
                .font(settings.metaFont)
                .foregroundStyle(XDTheme.secondaryText)
            }
        }
        .xdCard()
    }

    @ViewBuilder
    private func feedMenu(_ post: XDPost) -> some View {
        if unread.unreadCount(for: post.id) > 0 {
            Button {
                unread.markRead([post.id])
            } label: { Label("标记已读", systemImage: "checkmark") }
        }
        Button {
            library.togglePin(post.id)
        } label: {
            Label(library.current.pinned.contains(post.id) ? "取消置顶" : "置顶",
                  systemImage: "pin")
        }
        Menu("移至分组") {
            Button("未分组") { library.assign(post.id, to: nil) }
            ForEach(library.current.groups) { group in
                Button(group.name) { library.assign(post.id, to: group.id) }
            }
            Button("管理分组") { showGroups = true }
        }
        if replyCounts.failedIDs.contains(post.id) {
            Button {
                retryReplyCount(post.id)
            } label: { Label("重试获取回复数", systemImage: "arrow.clockwise") }
        }
        Button(role: .destructive) {
            Task { await vm.unsubscribe(post) }
        } label: { Label("取消订阅", systemImage: "bookmark.slash") }
    }

    private var feedList: some View {
        let items = visibleItems
        return ScrollView {
            LazyVStack(spacing: XDTheme.cardSpacing) {
                ForEach(items) { post in
                    feedRow(post)
                }

                if items.isEmpty && !vm.items.isEmpty {
                    EmptyStateView(icon: "magnifyingglass",
                                   title: settings.feedOnlyUpdated ? "暂无更新" : "没有匹配的订阅",
                                   subtitle: "切换分组或筛选条件后再试。")
                } else {
                    ListStatusView(isLoading: vm.isLoading,
                                   error: vm.error,
                                   isEmpty: vm.items.isEmpty,
                                   emptyIcon: "bookmark",
                                   emptyTitle: "还没有订阅",
                                   emptySubtitle: "在串页面点右上角书签即可订阅。\n订阅 ID 可在「我的 → 设置 → 订阅」中查看和同步。",
                                   retry: { Task { await vm.retry() } })
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .refreshable { await vm.refresh() }
    }

    private var selectionBar: some View {
        VStack(spacing: 12) {
            HStack {
                let visibleIDs = Set(visibleItems.map(\.id))
                Button(selectedIDs == visibleIDs && !visibleIDs.isEmpty ? "取消全选" : "全选当前列表") {
                    selectedIDs = selectedIDs == visibleIDs ? [] : visibleIDs
                }
                Spacer()
                if vm.isBatchUpdating { ProgressView().controlSize(.small) }
                Text("已选 \(selectedIDs.count) 个").foregroundStyle(XDTheme.secondaryText)
            }
            HStack {
                Menu {
                    Button("未分组") { moveSelection(to: nil) }
                    ForEach(library.current.groups) { group in
                        Button(group.name) { moveSelection(to: group.id) }
                    }
                } label: { Label("移至分组", systemImage: "folder") }
                Spacer()
                Button {
                    unread.markRead(selectedIDs)
                    selectedIDs = []
                    isSelecting = false
                } label: { Label("标记已读", systemImage: "checkmark") }
                Spacer()
                Button(role: .destructive) { showBatchUnsubscribe = true } label: {
                    Image(systemName: "bookmark.slash")
                }
                .accessibilityLabel("取消选中订阅")
            }
            .disabled(selectedIDs.isEmpty)
        }
        .font(.subheadline)
        .padding(12)
        .background(.regularMaterial)
        .disabled(vm.isBatchUpdating || vm.isLoading || vm.isRestoring)
    }

    private func moveSelection(to group: UUID?) {
        library.assign(selectedIDs, to: group)
        selectedIDs = []
        isSelecting = false
    }

    @ViewBuilder
    private func replyCountLabel(for post: XDPost) -> some View {
        HStack(spacing: 5) {
            Label(post.replyCount.map(String.init) ?? "—", systemImage: "bubble.left")
            let added = unread.unreadCount(for: post.id)
            if added > 0 {
                Text(verbatim: "+\(added)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                    .accessibilityLabel("\(added) 条未读回复")
            }
            if replyCounts.loadingIDs.contains(post.id) {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("正在获取回复数")
            } else if replyCounts.failedIDs.contains(post.id) {
                Button {
                    retryReplyCount(post.id)
                } label: {
                    Text(post.replyCount == nil ? "获取失败，重试" : "更新失败，重试")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func retryReplyCount(_ id: Int) {
        replyCounts.request([id], cookie: CookieStore.shared.cookieValue, force: true)
    }

    private var groupName: String {
        if selectedGroup == "all" { return "全部订阅" }
        if selectedGroup == "ungrouped" { return "未分组" }
        return library.current.groups.first { $0.id.uuidString == selectedGroup }?.name ?? "全部订阅"
    }

}

struct FeedGroupsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = FeedLibraryStore.shared
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(library.current.groups) { group in
                    Button(group.name) {
                        editingID = group.id
                        name = group.name
                        showEditor = true
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { library.removeGroup(group.id) }
                    }
                }
                Button {
                    editingID = nil
                    name = ""
                    showEditor = true
                } label: { Label("新建分组", systemImage: "plus") }
            }
            .navigationTitle("订阅分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .alert(editingID == nil ? "新建分组" : "重命名", isPresented: $showEditor) {
                TextField("分组名称", text: $name)
                Button("保存") { library.saveGroup(id: editingID ?? UUID(), name: name) }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
