import SwiftUI

struct ThreadAnchor: Equatable {
    var postId: Int
    var tick: Int
}

private struct ReplyFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
final class ThreadViewModel: ObservableObject {
    @Published var mainPost: XDPost?
    @Published var tip: XDPost?
    @Published var replies: [XDPost] = []
    @Published var loadedPages: [Int] = []
    @Published var isLoading = false
    @Published var isPositioning = false
    @Published var isSwitchingMode = false
    @Published var error: String?
    @Published private(set) var onlyPo = false
    @Published var pageAnchor: ThreadAnchor?

    var isSubscribed: Bool { SubscriptionCache.shared.contains(mainPostId) }

    let mainPostId: Int
    private(set) var lastVisibleId: Int?
    private var visibleIds = Set<Int>()
    private var loadedIds = Set<Int>()
    private var replyPage: [Int: Int] = [:]
    private var inflight: Task<Void, Never>?
    private var anchorTick = 0
    private(set) var contextID = UUID()
    private var requestID: UUID?
    private var isReadingActive = true
    private var didFinishInitialRestoration = false
    private enum FailedLoad {
        case page(Int, reset: Bool, prepend: Bool, force: Bool)
        case position(Int, postId: Int?)
    }
    private var failedLoad: FailedLoad?

    init(mainPostId: Int, onlyPo: Bool = false) {
        self.mainPostId = mainPostId
        self.onlyPo = onlyPo
    }

    var maxPage: Int { max(1, mainPost?.maxPage ?? 1) }
    var currentLastPage: Int { loadedPages.max() ?? 1 }
    var currentFirstPage: Int { loadedPages.min() ?? 1 }
    var canLoadMore: Bool { currentLastPage < maxPage }

    func reset(onlyPo: Bool, page: Int? = nil, anchorPostId: Int? = nil) async {
        guard isReadingActive else { return }
        saveReadProgress()
        // Cancellation is best effort; the request identity also rejects late responses.
        contextID = UUID()
        let context = contextID
        requestID = nil
        inflight?.cancel()
        inflight = nil
        isLoading = false
        isSwitchingMode = true
        defer { if context == contextID { isSwitchingMode = false } }
        error = nil
        failedLoad = nil
        tip = nil
        pageAnchor = nil
        isPositioning = false
        self.onlyPo = onlyPo
        let progress = page == nil ? HistoryStore.shared.readProgress(for: mainPostId, onlyPo: onlyPo) : nil
        let targetPage = max(1, page ?? progress?.page ?? 1)
        let targetPostId = page == nil ? progress?.postId : anchorPostId
        replies = []
        loadedPages = []
        loadedIds = []
        replyPage = [:]
        visibleIds = []
        lastVisibleId = nil
        HistoryStore.shared.noteReading(mainPostId: mainPostId, page: targetPage,
                                        postId: targetPostId, onlyPo: onlyPo)
        await openPage(targetPage, anchorPostId: targetPostId)
    }

    func saveReadProgress() {
        // Loaded replies are not necessarily visible while restoring the scroll position.
        guard isReadingActive, didFinishInitialRestoration, !isPositioning,
              let candidate = lastVisibleId, let page = replyPage[candidate] else { return }
        HistoryStore.shared.saveProgress(mainPostId: mainPostId,
                                         page: page,
                                         postId: candidate,
                                         onlyPo: onlyPo)
    }

    func resumeReading() {
        isReadingActive = true
    }

    func beginInitialRestoration() {
        didFinishInitialRestoration = false
    }

    func stopReading() {
        saveReadProgress()
        isReadingActive = false
        contextID = UUID()
        requestID = nil
        inflight?.cancel()
        inflight = nil
        isLoading = false
        isPositioning = false
        isSwitchingMode = false
    }

    func finishInitialRestoration(at postId: Int? = nil) {
        guard isReadingActive, !didFinishInitialRestoration else { return }
        didFinishInitialRestoration = true
        if let postId, replyPage[postId] != nil {
            recordReadingAnchor(postId)
        } else {
            updateReadingAnchor()
        }
    }

    func finishPositioning(at postId: Int) {
        isPositioning = false
        recordReadingAnchor(postId)
    }

    func refreshCurrentPage() async {
        Task { await CookieStore.shared.syncDisplayIds(force: true) }
        let context = contextID
        await inflight?.value
        guard context == contextID else { return }
        await load(page: currentFirstPage, reset: true)
    }

    func reloadLastPage() async {
        let context = contextID
        await inflight?.value
        guard context == contextID else { return }
        let wasAtEnd = !loadedPages.isEmpty && currentLastPage >= maxPage
        await load(page: currentLastPage, force: true)
        guard context == contextID, wasAtEnd, error == nil else { return }
        while currentLastPage < maxPage {
            let nextPage = currentLastPage + 1
            await load(page: nextPage)
            if context != contextID || error != nil || !loadedPages.contains(nextPage) { break }
        }
    }

    func refreshLastPage() async {
        Task { await CookieStore.shared.syncDisplayIds(force: true) }
        let context = contextID
        await inflight?.value
        guard context == contextID else { return }
        let before = replies.count
        let previousMaxPage = maxPage
        await reloadLastPage()
        guard context == contextID else { return }
        if replies.count == before && maxPage == previousMaxPage && error == nil {
            Toast.shared.show("没有新回复")
        }
    }

    func load(page: Int, reset: Bool = false, prepend: Bool = false, force: Bool = false) async {
        guard isReadingActive, !isLoading else { return }
        guard page >= 1 else { return }
        if !reset && !force && loadedPages.contains(page) { return }
        let request = UUID()
        let mode = onlyPo
        let cookie = CookieStore.shared.cookieValue
        requestID = request
        isLoading = true
        let task = Task { @MainActor in
            await self.performLoad(page: page, reset: reset, prepend: prepend,
                                   force: force, request: request, onlyPo: mode, cookie: cookie)
        }
        inflight = task
        await task.value
    }

    private func performLoad(page: Int, reset: Bool, prepend: Bool, force: Bool,
                             request: UUID, onlyPo: Bool, cookie: String?) async {
        guard requestID == request, !Task.isCancelled else { return }
        defer {
            if requestID == request {
                inflight = nil
                requestID = nil
                isLoading = false
            }
        }
        do {
            let result = try await XDAPI.shared.thread(mainPostId: mainPostId, page: page, onlyPo: onlyPo, cookie: cookie)
            guard requestID == request, self.onlyPo == onlyPo, !Task.isCancelled else { return }
            mainPost = result.mainPost
            if result.tip != nil { tip = result.tip }
            HistoryStore.shared.recordObservedReplies(result.replies,
                                                      mainPostId: mainPostId,
                                                      forumId: result.mainPost.forumId)
            let observedReplies = result.replies
            let observedForumId = result.mainPost.forumId
            let observedThreadId = mainPostId
            Task { @MainActor in
                await CookieStore.shared.syncDisplayIds()
                HistoryStore.shared.recordObservedReplies(observedReplies,
                                                          mainPostId: observedThreadId,
                                                          forumId: observedForumId)
            }

            if reset {
                replies = []
                loadedPages = []
                loadedIds = []
                replyPage = [:]
                visibleIds = []
                lastVisibleId = nil
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
            failedLoad = nil
            error = nil

            if let mp = mainPost {
                HistoryStore.shared.recordBrowse(mp, page: page, onlyPo: onlyPo)
            }
        } catch {
            guard requestID == request, self.onlyPo == onlyPo, !Task.isCancelled else { return }
            failedLoad = .page(page, reset: reset, prepend: prepend, force: force)
            self.error = error.localizedDescription
        }
    }

    func updateVisibleReplies(_ frames: [Int: CGRect], in viewport: CGRect) {
        guard isReadingActive, viewport.width > 0, viewport.height > 0 else { return }
        // LazyVStack can retain offscreen rows; lifecycle callbacks are not visibility.
        visibleIds = Set(frames.compactMap { id, frame in
            frame.intersects(viewport) ? id : nil
        })
        updateReadingAnchor()
    }

    private func updateReadingAnchor() {
        guard let top = replies.first(where: { visibleIds.contains($0.id) }) else { return }
        recordReadingAnchor(top.id)
    }

    private func recordReadingAnchor(_ postId: Int) {
        guard isReadingActive, didFinishInitialRestoration, !isPositioning,
              lastVisibleId != postId, let page = replyPage[postId] else { return }
        lastVisibleId = postId
        HistoryStore.shared.noteReading(mainPostId: mainPostId,
                                        page: page,
                                        postId: postId,
                                        onlyPo: onlyPo)
        // Keep confirmed progress durable even if the app exits before onDisappear.
        saveReadProgress()
    }

    func loadNextIfNeeded(current post: XDPost) async {
        guard !isLoading, !isPositioning, error == nil,
              canLoadMore, replies.last?.id == post.id else { return }
        await load(page: currentLastPage + 1)
    }

    func openPage(_ page: Int, anchorPostId: Int? = nil) async {
        guard isReadingActive, !isLoading else { return }
        let context = contextID
        let target = max(1, page)
        isPositioning = true
        await load(page: target, reset: true)
        guard context == contextID else { return }
        guard error == nil else {
            // A failed jump must not prepend pages to the old list or lose its target.
            failedLoad = .position(target, postId: anchorPostId)
            isPositioning = false
            return
        }
        if anchorPostId == mainPostId {
            // The main post uses the view's "main" anchor, not a reply-page anchor.
            isPositioning = false
            return
        }
        var anchorId = anchorPostId.flatMap { id in replies.contains(where: { $0.id == id }) ? id : nil }
        if anchorId == nil, target > 1 { anchorId = replies.first?.id }
        guard let anchor = anchorId else {
            isPositioning = false
            return
        }
        if target > 1 { await load(page: target - 1, prepend: true) }
        guard context == contextID else { return }
        anchorTick += 1
        pageAnchor = ThreadAnchor(postId: anchor, tick: anchorTick)
    }

    func page(of id: Int) -> Int? { replyPage[id] }

    func retryLoad() async {
        guard isReadingActive, !isLoading else { return }
        guard let failedLoad else {
            // The empty-state button also uses this action after a successful empty page.
            if replies.isEmpty { await refreshCurrentPage() }
            return
        }
        switch failedLoad {
        case let .page(page, reset, prepend, force):
            await load(page: page, reset: reset, prepend: prepend, force: force)
        case let .position(page, postId):
            await openPage(page, anchorPostId: postId)
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
    @Environment(\.scenePhase) private var scenePhase
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
        var onlyPo: Bool
    }

    init(mainPostId: Int, initialPage: Int = 1, onlyPo: Bool = false, jumpToPostId: Int? = nil) {
        self.mainPostId = mainPostId
        self.initialPage = initialPage
        self.onlyPo = onlyPo
        self.jumpToPostId = jumpToPostId
        _vm = StateObject(wrappedValue: ThreadViewModel(mainPostId: mainPostId, onlyPo: onlyPo))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                XDTheme.background.ignoresSafeArea()

                GeometryReader { viewport in
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
                                    .background(GeometryReader { geometry in
                                        Color.clear.preference(key: ReplyFramesKey.self,
                                            value: [reply.id: geometry.frame(in: .named("threadViewport"))])
                                    })
                                    .task(id: vm.isPositioning) { await vm.loadNextIfNeeded(current: reply) }
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
                    .coordinateSpace(name: "threadViewport")
                    .onPreferenceChange(ReplyFramesKey.self) { frames in
                        guard scenePhase == .active else { return }
                        vm.updateVisibleReplies(frames, in: CGRect(origin: .zero, size: viewport.size))
                    }
                    .opacity((restoreTarget == nil || didInitialJump) && !vm.isPositioning ? 1 : 0)
                    .animation(.easeIn(duration: 0.15), value: vm.isPositioning)
                    .animation(.easeIn(duration: 0.15), value: didInitialJump)
                    .refreshable { await vm.refreshCurrentPage() }
                    .onChange(of: initialLoadDone) { _ in restoreScroll(proxy) }
                    .onChange(of: vm.pageAnchor) { anchor in
                        guard let anchor else { return }
                        if restoreTarget == nil || didInitialJump {
                            proxy.scrollTo(anchor.postId, anchor: .top)
                        }
                        vm.finishPositioning(at: anchor.postId)
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
        .onAppear { vm.resumeReading() }
        .task {
            if !initialLoadDone || vm.loadedPages.isEmpty {
                let context = vm.contextID
                let initialTarget = initialLoadDone ? nil : jumpToPostId
                let progress = initialTarget == nil
                    ? HistoryStore.shared.readProgress(for: mainPostId, onlyPo: vm.onlyPo) : nil
                let start = progress?.page ?? (initialLoadDone ? 1 : initialPage)
                let target = initialTarget ?? progress?.postId
                vm.beginInitialRestoration()
                initialLoadDone = false
                didInitialJump = false
                restoreTarget = target
                HistoryStore.shared.noteReading(mainPostId: mainPostId, page: start,
                                                postId: target, onlyPo: vm.onlyPo)
                await vm.openPage(start, anchorPostId: target)
                guard context == vm.contextID else { return }
                if vm.error == nil, let jumpToPostId = initialTarget, jumpToPostId != mainPostId,
                   !vm.replies.contains(where: { $0.id == jumpToPostId }),
                   let page = try? await XDAPI.shared.locateReply(jumpToPostId, in: mainPostId,
                                                                  onlyPo: vm.onlyPo,
                                                                  cookie: CookieStore.shared.cookieValue) {
                    guard context == vm.contextID else { return }
                    await vm.openPage(page, anchorPostId: jumpToPostId)
                }
                guard context == vm.contextID else { return }
                initialLoadDone = true
            }
        }
        .onChange(of: app.threadRefreshTick[mainPostId] ?? 0) { _ in
            Task { await vm.reloadLastPage() }
        }
        .onDisappear {
            vm.stopReading()
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
                        // Mode switching replaces the initial scroll restoration.
                        // Let reset() restore the new mode through pageAnchor instead.
                        restoreTarget = nil
                        didInitialJump = true
                        initialLoadDone = true
                        await vm.reset(onlyPo: !vm.onlyPo)
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
        guard initialLoadDone else { return }
        guard !didInitialJump, let target = restoreTarget else {
            vm.finishInitialRestoration()
            return
        }
        if vm.replies.contains(where: { $0.id == target }) {
            didInitialJump = true
            proxy.scrollTo(target, anchor: .top)
            vm.finishInitialRestoration(at: target)
        } else {
            didInitialJump = true
            vm.finishInitialRestoration()
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
            returnAnchor = ReturnAnchor(page: originPage, postId: originId, onlyPo: vm.onlyPo)
        }
        // Reference lookup returns a page in the full thread. Loaded replies can
        // still be reached in the current mode without using that page number.
        let targetIsLoaded = req.postId == mainPostId || vm.replies.contains(where: { $0.id == req.postId })
        await scrollTo(postId: req.postId, page: req.page,
                       onlyPo: targetIsLoaded ? vm.onlyPo : false, proxy: proxy)
        Haptics.light()
    }

    private func returnToOrigin(_ proxy: ScrollViewProxy) async {
        guard let anchor = returnAnchor else { return }
        withAnimation(.easeOut(duration: 0.2)) { returnAnchor = nil }
        await scrollTo(postId: anchor.postId, page: anchor.page, onlyPo: anchor.onlyPo, proxy: proxy)
        Haptics.light()
    }

    private func scrollTo(postId: Int, page: Int, onlyPo: Bool, proxy: ScrollViewProxy) async {
        if vm.onlyPo != onlyPo {
            await vm.reset(onlyPo: onlyPo, page: page, anchorPostId: postId)
            if postId == mainPostId {
                proxy.scrollTo("main", anchor: .top)
            }
        } else if postId == mainPostId {
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
