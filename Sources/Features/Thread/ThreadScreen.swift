import SwiftUI

struct ThreadAnchor: Equatable {
    var postId: Int
    var tick: Int
}

@MainActor
final class ThreadViewModel: ObservableObject {
    @Published var mainPost: XDPost?
    @Published var tip: XDPost?
    @Published var replies: [XDPost] = []
    @Published var loadedPages: [Int] = []
    @Published var isLoading = false
    @Published var isPositioning = false
    @Published var error: String?
    @Published var onlyPo = false
    @Published var pageAnchor: ThreadAnchor?

    var isSubscribed: Bool { SubscriptionCache.shared.contains(mainPostId) }

    let mainPostId: Int
    private(set) var lastVisibleId: Int?
    private var loadedIds = Set<Int>()
    private var replyPage: [Int: Int] = [:]
    private var inflight: Task<Void, Never>?
    private var anchorTick = 0

    init(mainPostId: Int) {
        self.mainPostId = mainPostId
    }

    var maxPage: Int { max(1, mainPost?.maxPage ?? 1) }
    var currentLastPage: Int { loadedPages.max() ?? 1 }
    var currentFirstPage: Int { loadedPages.min() ?? 1 }
    var canLoadMore: Bool { currentLastPage < maxPage }

    func reset(onlyPo: Bool) async {
        self.onlyPo = onlyPo
        replies = []
        loadedPages = []
        loadedIds = []
        replyPage = [:]
        await load(page: 1, reset: true)
    }

    func refreshCurrentPage() async {
        await inflight?.value
        await load(page: currentFirstPage, reset: true)
    }

    func reloadLastPage() async {
        await inflight?.value
        await load(page: currentLastPage, force: true)
    }

    func refreshLastPage() async {
        let before = replies.count
        await reloadLastPage()
        if replies.count == before && error == nil {
            Toast.shared.show("没有新回复")
        }
    }

    func load(page: Int, reset: Bool = false, prepend: Bool = false, force: Bool = false) async {
        guard !isLoading else { return }
        guard page >= 1 else { return }
        if !reset && !force && loadedPages.contains(page) { return }
        let task = Task { @MainActor in await self.performLoad(page: page, reset: reset, prepend: prepend) }
        inflight = task
        await task.value
        inflight = nil
    }

    private func performLoad(page: Int, reset: Bool, prepend: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let cookie = CookieStore.shared.cookieValue
            let result = try await XDAPI.shared.thread(mainPostId: mainPostId, page: page, onlyPo: onlyPo, cookie: cookie)
            mainPost = result.mainPost
            if result.tip != nil { tip = result.tip }

            if reset {
                replies = []
                loadedPages = []
                loadedIds = []
                replyPage = [:]
            }
            let blacklist = BlacklistStore.shared
            let fresh = result.replies.filter { !loadedIds.contains($0.id) && !blacklist.shouldHide($0) }
            fresh.forEach { loadedIds.insert($0.id) }
            fresh.forEach { replyPage[$0.id] = page }
            if prepend {
                replies.insert(contentsOf: fresh, at: 0)
            } else {
                replies.append(contentsOf: fresh)
            }
            if !loadedPages.contains(page) { loadedPages.append(page); loadedPages.sort() }
            error = nil

            if let mp = mainPost {
                HistoryStore.shared.recordBrowse(mp, page: page)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func noteVisible(_ postId: Int) {
        lastVisibleId = postId
        HistoryStore.shared.noteReading(mainPostId: mainPostId,
                                        page: currentLastPage,
                                        postId: postId,
                                        onlyPo: onlyPo)
    }

    func loadNextIfNeeded(current post: XDPost) async {
        guard !isLoading, canLoadMore, replies.last?.id == post.id else { return }
        await load(page: currentLastPage + 1)
    }

    func openPage(_ page: Int, anchorPostId: Int? = nil) async {
        let target = max(1, page)
        isPositioning = true
        await load(page: target, reset: true)
        var anchorId = anchorPostId.flatMap { id in replies.contains(where: { $0.id == id }) ? id : nil }
        if anchorId == nil, target > 1 { anchorId = replies.first?.id }
        guard let anchor = anchorId else {
            isPositioning = false
            return
        }
        if target > 1 { await load(page: target - 1, prepend: true) }
        anchorTick += 1
        pageAnchor = ThreadAnchor(postId: anchor, tick: anchorTick)
    }

    func page(of id: Int) -> Int? { replyPage[id] }

    func retryLoad() async {
        await inflight?.value
        if replies.isEmpty {
            await load(page: currentLastPage, reset: true)
        } else if canLoadMore {
            await load(page: currentLastPage + 1)
        } else {
            await reloadLastPage()
        }
    }

    func jump(to page: Int) async {
        await openPage(min(page, maxPage))
    }

    func toggleSubscribe() async {
        let subscribing = !isSubscribed
        do {
            if subscribing {
                try await FeedService.shared.subscribe(mainPostId: mainPostId)
            } else {
                try await FeedService.shared.unsubscribe(mainPostId: mainPostId)
            }
            objectWillChange.send()
            Toast.shared.success(subscribing ? "订阅成功" : "已取消订阅")
        } catch {
            Toast.shared.error(error)
        }
    }

    func imageURLs() -> [URL] {
        var files: [String] = []
        if let f = mainPost?.imageFile { files.append(f) }
        files.append(contentsOf: replies.compactMap(\.imageFile))
        return files.map { XDURLs.shared.image($0) }
    }
}

struct ThreadScreen: View {
    let mainPostId: Int
    var initialPage: Int = 1
    var onlyPo: Bool = false
    var jumpToPostId: Int?

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var vm: ThreadViewModel
    @ObservedObject private var subscriptions = SubscriptionCache.shared
    @State private var showJumpSheet = false
    @State private var jumpPageText = ""
    @State private var didInitialJump = false
    @State private var restoreTarget: Int?
    @State private var initialLoadDone = false
    @State private var returnAnchor: ReturnAnchor?
    @State private var highlightId: Int?
    @State private var highlightTask: Task<Void, Never>?

    private struct ReturnAnchor {
        var page: Int
        var postId: Int
    }

    init(mainPostId: Int, initialPage: Int = 1, onlyPo: Bool = false, jumpToPostId: Int? = nil) {
        self.mainPostId = mainPostId
        self.initialPage = initialPage
        self.onlyPo = onlyPo
        self.jumpToPostId = jumpToPostId
        _vm = StateObject(wrappedValue: ThreadViewModel(mainPostId: mainPostId))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                XDTheme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: XDTheme.cardSpacing) {
                        if let main = vm.mainPost {
                            mainPostCard(main)
                                .id("main")
                        }

                        if let tip = vm.tip {
                            PostBodyView(post: tip)
                                .xdCard()
                        }

                        if vm.currentFirstPage > 1 {
                            Button {
                                Task { await vm.load(page: vm.currentFirstPage - 1, prepend: true) }
                            } label: {
                                Label(String(format: "加载上一页（第 %d 页）", vm.currentFirstPage - 1),
                                      systemImage: "arrow.up")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.bordered)
                            .padding(.vertical, 4)
                        }

                        ForEach(vm.replies) { reply in
                            replyCard(reply)
                                .id(reply.id)
                                .onAppear { vm.noteVisible(reply.id) }
                                .task { await vm.loadNextIfNeeded(current: reply) }
                        }

                        ListStatusView(isLoading: vm.isLoading,
                                       error: vm.error,
                                       isEmpty: vm.replies.isEmpty,
                                       reachedEnd: !vm.canLoadMore,
                                       emptyIcon: "bubble.left",
                                       emptyTitle: "还没有回复",
                                       retry: { Task { await vm.retryLoad() } },
                                       refresh: { Task { await vm.refreshLastPage() } })
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .opacity((restoreTarget == nil || didInitialJump) && !vm.isPositioning ? 1 : 0)
                .animation(.easeIn(duration: 0.15), value: vm.isPositioning)
                .animation(.easeIn(duration: 0.15), value: didInitialJump)
                .refreshable { await vm.refreshCurrentPage() }
                .onChange(of: initialLoadDone) { _ in restoreScroll(proxy) }
                .onChange(of: vm.pageAnchor) { anchor in
                    if let anchor, restoreTarget == nil || didInitialJump {
                        proxy.scrollTo(anchor.postId, anchor: .top)
                    }
                    vm.isPositioning = false
                }
                .onChange(of: vm.replies.count) { _ in
                    guard initialLoadDone else { return }
                    restoreScroll(proxy)
                }
                .onChange(of: app.threadJump) { req in
                    guard let req, req.threadId == mainPostId,
                          app.activeThreadId == mainPostId else { return }
                    app.threadJump = nil
                    Task { await performJump(req, proxy: proxy) }
                }

                replyButton

                if returnAnchor != nil {
                    returnButton(proxy)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .navigationTitle(vm.onlyPo ? "只看 Po" : String(format: "No.%d", mainPostId))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showJumpSheet) { jumpSheet }
        .task {
            if vm.mainPost == nil {
                let progress = jumpToPostId == nil ? HistoryStore.shared.readProgress(for: mainPostId) : nil
                let start = progress?.page ?? initialPage
                let target = jumpToPostId ?? progress?.postId
                restoreTarget = target
                vm.onlyPo = onlyPo
                HistoryStore.shared.noteReading(mainPostId: mainPostId, page: start,
                                                postId: target, onlyPo: onlyPo)
                await vm.openPage(start)
                initialLoadDone = true
            }
        }
        .onChange(of: app.threadRefreshTick[mainPostId] ?? 0) { _ in
            Task { await vm.reloadLastPage() }
        }
        .onDisappear {
            HistoryStore.shared.saveProgress(mainPostId: mainPostId,
                                             page: vm.currentLastPage,
                                             postId: vm.lastVisibleId ?? vm.replies.last?.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                Task { await vm.toggleSubscribe() }
            } label: {
                Image(systemName: subscriptions.contains(mainPostId) ? "bookmark.fill" : "bookmark")
            }

            Menu {
                Button {
                    Task {
                        vm.onlyPo.toggle()
                        await vm.reset(onlyPo: vm.onlyPo)
                    }
                } label: {
                    Label(vm.onlyPo ? "看全部回复" : "只看 Po", systemImage: "person.crop.circle")
                }

                Button {
                    showJumpSheet = true
                } label: { Label(String(format: "跳页（共 %d 页）", vm.maxPage), systemImage: "arrow.up.arrow.down") }

                Divider()

                Button {
                    copyToPasteboard(XDURLs.shared.webThreadURL(mainPostId, page: vm.currentLastPage).absoluteString,
                                     message: "已复制链接")
                } label: { Label("复制链接", systemImage: "link") }

                Button(role: .destructive) {
                    BlacklistStore.shared.block(post: mainPostId, title: vm.mainPost?.title ?? "")
                    Toast.shared.show("已屏蔽该串")
                } label: { Label("屏蔽该串", systemImage: "eye.slash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var jumpSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("页码 1 - \(vm.maxPage)", text: $jumpPageText)
                        .keyboardType(.numberPad)
                    Stepper("第 \(Int(jumpPageText) ?? vm.currentLastPage) 页",
                            value: Binding(get: { Int(jumpPageText) ?? vm.currentLastPage },
                                           set: { jumpPageText = "\($0)" }),
                            in: 1...max(1, vm.maxPage))
                }
                Section {
                    Button("跳到第一页") { jump(1) }
                    Button("跳到最后一页") { jump(vm.maxPage) }
                }
            }
            .navigationTitle("跳页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("跳转") { jump(Int(jumpPageText) ?? 1) }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showJumpSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func restoreScroll(_ proxy: ScrollViewProxy) {
        guard !didInitialJump, let target = restoreTarget else { return }
        if vm.replies.contains(where: { $0.id == target }) {
            didInitialJump = true
            proxy.scrollTo(target, anchor: .top)
        } else if initialLoadDone {
            didInitialJump = true
        }
    }

    private func jump(_ page: Int) {
        showJumpSheet = false
        Task { await vm.jump(to: page) }
    }

    private func refTapAction(from postId: Int) -> OpenURLAction {
        OpenURLAction { url in
            if XDContent.postId(fromRefURL: url) != nil {
                app.referenceOrigin = (threadId: mainPostId, postId: postId)
            }
            if app.handle(url: url) { return .handled }
            return .systemAction
        }
    }

    private func performJump(_ req: AppState.ThreadJump, proxy: ScrollViewProxy) async {
        let originId: Int
        if let origin = app.referenceOrigin, origin.threadId == mainPostId {
            originId = origin.postId
        } else {
            originId = vm.lastVisibleId ?? mainPostId
        }
        app.referenceOrigin = nil
        let originPage = vm.page(of: originId) ?? vm.currentFirstPage
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            returnAnchor = ReturnAnchor(page: originPage, postId: originId)
        }
        await scrollTo(postId: req.postId, page: req.page, proxy: proxy)
        Haptics.light()
    }

    private func returnToOrigin(_ proxy: ScrollViewProxy) async {
        guard let anchor = returnAnchor else { return }
        withAnimation(.easeOut(duration: 0.2)) { returnAnchor = nil }
        await scrollTo(postId: anchor.postId, page: anchor.page, proxy: proxy)
        Haptics.light()
    }

    private func scrollTo(postId: Int, page: Int, proxy: ScrollViewProxy) async {
        if postId == mainPostId {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("main", anchor: .top) }
        } else if vm.replies.contains(where: { $0.id == postId }) {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(postId, anchor: .top) }
        } else {
            await vm.openPage(page, anchorPostId: postId)
        }
        flashHighlight(postId)
    }

    private func flashHighlight(_ id: Int) {
        highlightTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { highlightId = id }
        highlightTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { highlightId = nil }
        }
    }

    @ViewBuilder
    private func highlightBorder(for id: Int) -> some View {
        if highlightId == id {
            RoundedRectangle(cornerRadius: XDTheme.cardRadius, style: .continuous)
                .stroke(settings.accent.color, lineWidth: 2)
        }
    }

    private func returnButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            Task { await returnToOrigin(proxy) }
        } label: {
            Label("回到引用处", systemImage: "arrow.uturn.backward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(settings.accent.color))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .padding(.leading, 18)
        .padding(.bottom, 24)
    }

    private func mainPostCard(_ main: XDPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PostBodyView(post: main, isPo: true, onTapImage: openImage)
                .zIndex(1)
            if let fid = main.forumId, fid > 0 {
                XDBadge(text: ForumStore.shared.name(forId: fid), color: XDTheme.link)
            }
        }
        .environment(\.openURL, refTapAction(from: main.id))
        .xdCard()
        .overlay { highlightBorder(for: main.id) }
        .contextMenu { postMenu(main) }
    }

    private func replyCard(_ reply: XDPost) -> some View {
        PostBodyView(post: reply,
                     poHash: vm.mainPost?.userHash,
                     showForum: false,
                     onTapImage: openImage)
            .environment(\.openURL, refTapAction(from: reply.id))
            .xdCard()
            .overlay { highlightBorder(for: reply.id) }
            .contextMenu { postMenu(reply) }
    }

    @ViewBuilder
    private func postMenu(_ post: XDPost) -> some View {
        Button {
            app.compose = .reply(mainPostId: mainPostId, quote: ">>No.\(post.id)\n")
        } label: { Label("引用回复", systemImage: "quote.opening") }

        postCommonMenuItems(post)
    }

    private func openImage(_ url: URL) {
        let all = vm.imageURLs()
        let idx = all.firstIndex(of: url) ?? 0
        app.imageViewer = ImageViewerPayload(images: all.isEmpty ? [url] : all, index: idx)
    }

    private var replyButton: some View {
        XDFloatingButton(systemImage: "arrowshape.turn.up.left.fill") {
            guard CookieStore.shared.hasCookie else {
                Toast.shared.error("回复需要先添加饼干")
                return
            }
            app.compose = .reply(mainPostId: mainPostId, quote: nil)
            Haptics.medium()
        }
    }
}

struct ReferenceSheet: View {
    let postId: Int

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var stack: [Int] = []
    @State private var post: XDPost?
    @State private var error: String?
    @State private var isLoading = false
    @State private var isChecking = false
    @State private var jumpFailed = false
    @State private var imageViewer: ImageViewerPayload?

    private var currentId: Int { stack.last ?? postId }

    private func jumpToReply(thread: Int, post: XDPost) async {
        isChecking = true
        defer { isChecking = false }
        do {
            if let page = try await XDAPI.shared.locateReply(post.id, in: thread,
                                                             cookie: CookieStore.shared.cookieValue) {
                app.requestThreadJump(threadId: thread, page: page, postId: post.id)
                dismiss()
                return
            }
        } catch {}
        withAnimation { jumpFailed = true }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if jumpFailed {
                        EmptyStateView(icon: "exclamationmark.triangle",
                                       title: "无法跳转",
                                       subtitle: "该引用不在当前串内（跨串引用或已被删除）")
                    } else if let post, !isLoading {
                        PostBodyView(post: post, onTapImage: { url in
                            imageViewer = ImageViewerPayload(images: [url], index: 0)
                        })
                        .xdCard()

                        if let main = post.mainPostId, main > 0 {
                            Button {
                                if main == app.activeThreadId {
                                    app.requestThreadJump(threadId: main, page: 1, postId: post.id)
                                } else {
                                    app.openThread(main, jumpTo: post.id)
                                }
                                dismiss()
                            } label: {
                                Label(main == app.activeThreadId
                                          ? (post.id == main ? "跳转到主串" : "跳转到该回复的位置")
                                          : String(format: "跳转到原串 No.%d", main),
                                      systemImage: "arrow.up.forward.app")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        } else if let current = app.activeThreadId {
                            Button {
                                Task { await jumpToReply(thread: current, post: post) }
                            } label: {
                                if isChecking {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Label("跳转到该回复的位置", systemImage: "arrow.up.forward.app")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isChecking)
                        }
                    } else if let error, !isLoading {
                        EmptyStateView(icon: "exclamationmark.triangle", title: "获取引用失败", subtitle: error)
                    } else {
                        InlineLoading(text: String(format: "正在获取 No.%d", currentId))
                    }
                }
                .padding(12)
            }
            .background(XDTheme.background)
            .navigationTitle(String(format: "引用 No.%d", currentId))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if stack.count > 1 {
                        Button {
                            stack.removeLast()
                        } label: { Label("返回", systemImage: "chevron.left") }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } }
            }
        }
        .fullScreenCover(item: $imageViewer) { payload in
            ImageViewerScreen(payload: payload)
        }
        .environment(\.openURL, OpenURLAction { url in
            if let id = XDContent.postId(fromRefURL: url) {
                if id != currentId { stack.append(id) }
                return .handled
            }
            return .systemAction
        })
        .onAppear { if stack.isEmpty { stack = [postId] } }
        .task(id: currentId) { await load() }
    }

    private func load() async {
        isLoading = true
        jumpFailed = false
        defer { isLoading = false }
        do {
            post = try await XDAPI.shared.reference(postId: currentId,
                                                    cookie: CookieStore.shared.cookieValue)
            error = nil
        } catch {
            post = nil
            self.error = error.localizedDescription
        }
    }
}
