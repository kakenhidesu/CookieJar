import SwiftUI

struct HistoryScreen: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var readingSearch = ReadingSearchStore.shared
    @ObservedObject private var blacklist = BlacklistStore.shared
    @ObservedObject private var forums = ForumStore.shared
    @State private var segment = 0

    private func consumeSegmentRequest() {
        guard let requested = app.historySegmentRequest else { return }
        segment = requested
        app.historySegmentRequest = nil
    }

    private var segmentName: String {
        switch segment {
        case 0: return "浏览"
        case 1: return "发串"
        default: return "回复"
        }
    }
    @State private var showClearConfirm = false
    @State private var legacyThread: PostRecord?
    @State private var query = ""
    @State private var searchFilter = ReadingSearchStore.Filter()
    @State private var contentMatches: [Int: ReadingSearchStore.Match] = [:]
    @State private var expandedThreads: Set<Int> = []
    @State private var blockedThreads: Set<Int> = []
    @State private var completedQuery = ""
    @State private var completedBlacklist: BlacklistStore.Payload?
    @State private var completedFilter: ReadingSearchStore.Filter?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchRetry = 0

    private struct SearchRequest: Equatable {
        var query: String
        var segment: Int
        var revision: Int
        var retry: Int
        var blacklist: BlacklistStore.Payload
        var filter: ReadingSearchStore.Filter
    }

    private var searchRequest: SearchRequest {
        SearchRequest(query: trimmedQuery, segment: segment, revision: readingSearch.revision,
                      retry: searchRetry, blacklist: blacklist.data, filter: searchFilter)
    }

    private func contentMatch(for id: Int) -> ReadingSearchStore.Match? {
        guard !trimmedQuery.isEmpty, isSearchCurrent else { return nil }
        return contentMatches[id]
    }

    private var isSearchCurrent: Bool {
        completedQuery == trimmedQuery && completedBlacklist == blacklist.data
            && completedFilter == searchFilter
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchForums: [(id: Int, name: String)] {
        let known = forums.orderedForums(includeHidden: true)
        let knownIds = Set(known.map(\.id))
        var savedIds = Set(history.browsing.compactMap(\.forumId))
        if let selected = searchFilter.forumId { savedIds.insert(selected) }
        return known.map { (id: $0.id, name: $0.showName) }
            + savedIds.subtracting(knownIds).sorted().map { (id: $0, name: forums.name(forId: $0)) }
    }

    private var filteredBrowsing: [(day: Date, records: [BrowseRecord])] {
        let q = trimmedQuery
        guard !q.isEmpty else { return history.browsingByDay }
        guard isSearchCurrent, searchError == nil else { return [] }
        let cal = Calendar.current
        let matched = history.browsing.filter { record in
            guard !blockedThreads.contains(record.id),
                  !ReadingSearchStore.isBlocked(record, by: blacklist.data) else { return false }
            if contentMatch(for: record.id) != nil { return true }
            guard searchFilter.includes(postId: record.id, threadId: record.id,
                                        forumId: record.forumId) else { return false }
            return record.title.localizedCaseInsensitiveContains(q)
                || record.preview.localizedCaseInsensitiveContains(q)
                || record.userHash.localizedCaseInsensitiveContains(q)
                || "\(record.id)".contains(q)
        }
        return Dictionary(grouping: matched) { cal.startOfDay(for: $0.browsedAt) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, records: $0.value) }
    }

    private var filteredPosts: [PostRecord] {
        let kind: PostRecord.Kind = segment == 1 ? .thread : .reply
        let base = history.posts.filter { $0.kind == kind }
        let q = trimmedQuery
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.content.localizedCaseInsensitiveContains(q)
                || ($0.postId.map { "\($0)" } ?? "").contains(q)
        }
    }

    var body: some View {
        ZStack {
            XDTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text("浏览").tag(0)
                    Text("发串").tag(1)
                    Text("回复").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if segment == 0 && !trimmedQuery.isEmpty {
                    VStack(spacing: 4) {
                        HStack {
                            Picker("搜索内容", selection: $searchFilter.scope) {
                                ForEach(ReadingSearchStore.ContentScope.allCases) { scope in
                                    Text(scope.rawValue).tag(scope)
                                }
                            }
                            .accessibilityLabel("搜索内容")
                            Spacer()
                            Picker("版块", selection: $searchFilter.forumId) {
                                Text("全部版块").tag(Int?.none)
                                ForEach(searchForums, id: \.id) { forum in
                                    Text(forum.name).tag(Optional(forum.id))
                                }
                            }
                            .accessibilityLabel("版块")
                        }
                        .pickerStyle(.menu)
                        .font(.subheadline)
                        if isSearching {
                            ProgressView("搜索中…").font(.caption)
                        }
                        if let error = searchError ?? readingSearch.writeError {
                            Text(error).font(.caption).foregroundStyle(XDTheme.secondaryText)
                            if searchError != nil {
                                Button("重试") { searchRetry += 1 }.font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                if segment == 0 { browsingList } else { postList }
            }
        }
        .navigationTitle("历史")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text(segment == 0 ? "搜索读过的串和回复" : "搜索\(segmentName)记录"))
        .task(id: searchRequest) { await searchLoadedContent() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: { Image(systemName: "trash") }
            }
        }
        .onAppear { consumeSegmentRequest() }
        .onChange(of: app.historySegmentRequest) { _ in consumeSegmentRequest() }
        .confirmationDialog("确定要清空吗？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空\(segmentName)记录", role: .destructive) {
                if segment == 0 {
                    history.clearBrowsing()
                } else {
                    history.clearPosts(kind: segment == 1 ? .thread : .reply)
                }
                Toast.shared.show("已清空")
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var browsingList: some View {
        Group {
            if history.browsing.isEmpty {
                EmptyStateView(icon: "clock", title: "还没有浏览记录",
                               subtitle: "可以在设置里关闭浏览记录。")
                Spacer()
            } else if filteredBrowsing.isEmpty {
                if !isSearching && isSearchCurrent && searchError == nil {
                    EmptyStateView(icon: "magnifyingglass", title: "没有匹配的记录",
                                   subtitle: "未在已加载的内容中找到关键词。")
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredBrowsing, id: \.day) { day, records in
                        Section(RelativeTime.day(day)) {
                            ForEach(records) { record in
                                Button {
                                    if let match = contentMatch(for: record.id) {
                                        app.openThread(record.id, page: match.page, onlyPo: match.onlyPo,
                                                       jumpTo: match.postId)
                                    } else {
                                        app.openThread(record.id, page: record.lastPage, jumpTo: record.lastPostId)
                                    }
                                } label: {
                                    recordRow(record)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        history.removeBrowse(id: record.id)
                                    } label: { Label("删除", systemImage: "trash") }
                                }
                                if let match = contentMatch(for: record.id), match.count > 1 {
                                    Button {
                                        if !expandedThreads.insert(record.id).inserted {
                                            expandedThreads.remove(record.id)
                                        }
                                    } label: {
                                        Label(expandedThreads.contains(record.id) ? "收起匹配" : "展开全部 \(match.count) 条匹配",
                                              systemImage: expandedThreads.contains(record.id) ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                    }
                                    if expandedThreads.contains(record.id) {
                                        ForEach(match.hits) { hit in
                                            Button {
                                                app.openThread(record.id, page: hit.page, onlyPo: hit.onlyPo,
                                                               jumpTo: hit.postId)
                                            } label: {
                                                SearchHitRow(hit: hit, threadId: record.id, query: trimmedQuery)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func recordRow(_ record: BrowseRecord) -> some View {
        let match = contentMatch(for: record.id)
        return HStack(alignment: .top, spacing: 10) {
            if !record.image.isEmpty && settings.showImages {
                AsyncThumb(file: record.image + record.imageExtension,
                           width: 56, height: 56, cornerRadius: 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title == "无标题" ? "No.\(record.id)" : record.title)
                    .font(settings.titleFont)
                    .foregroundStyle(XDTheme.text)
                    .lineLimit(1)
                HighlightedSearchText(text: match?.excerpt ?? record.preview, query: trimmedQuery)
                    .font(.system(size: 13))
                    .foregroundStyle(XDTheme.secondaryText)
                    .lineLimit(2)
                if let match {
                    Text(match.postId == record.id
                         ? "匹配主串 · 共 \(match.count) 条匹配"
                         : "匹配回复 No.\(match.postId) · 共 \(match.count) 条匹配")
                        .font(.caption2)
                        .foregroundStyle(settings.accent.color)
                }
                HStack(spacing: 8) {
                    Text(record.userHash)
                        .font(.system(size: 11, design: .monospaced))
                    if let match {
                        Text(match.onlyPo ? "只看 Po · 第 \(match.page) 页" : "第 \(match.page) 页")
                    } else {
                        Text("第 \(record.lastPage) 页")
                    }
                    if let c = record.replyCount { Text(verbatim: "\(c) 回应") }
                    Spacer()
                    Text(RelativeTime.display(record.browsedAt, relative: true))
                }
                .font(.system(size: 11))
                .foregroundStyle(XDTheme.secondaryText.opacity(0.85))
            }
        }
        .padding(.vertical, 3)
    }

    @MainActor
    private func searchLoadedContent() async {
        let request = searchRequest
        searchError = nil
        if completedQuery != request.query || completedBlacklist != request.blacklist
            || completedFilter != request.filter {
            contentMatches = [:]
            expandedThreads = []
            blockedThreads = []
            completedQuery = ""
        }
        guard request.segment == 0, !request.query.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        defer {
            if !Task.isCancelled && searchRequest == request { isSearching = false }
        }
        var result = ReadingSearchStore.SearchResult()
        var failure: String?
        do {
            try await Task.sleep(nanoseconds: 200_000_000)
            result = try await readingSearch.search(request.query, blacklist: request.blacklist,
                                                    browsing: history.browsing, filter: request.filter)
        } catch {
            failure = error.localizedDescription
        }
        guard !Task.isCancelled, searchRequest == request else { return }
        contentMatches = result.matches
        blockedThreads = result.blockedThreads
        completedQuery = request.query
        completedBlacklist = request.blacklist
        completedFilter = request.filter
        searchError = failure
    }

    private func openPost(_ record: PostRecord) {
        switch record.kind {
        case .reply:
            if let main = record.mainPostId, main > 0 {
                let replyId = record.status == .accepted ? record.postId : nil
                app.openThread(main, jumpTo: replyId)
            }
        case .thread:
            if record.status == .legacy, record.postId != nil {
                legacyThread = record
            } else if let fid = record.forumId, fid > 0 {
                app.openForum(id: fid, isTimeline: false)
                Toast.shared.show("新串编号未确认，已打开所在版块")
            } else {
                Toast.shared.show("新串编号未确认，无法直接打开")
            }
        }
    }

    @ViewBuilder
    private func postIdLabel(_ record: PostRecord) -> some View {
        switch record.status {
        case .accepted:
            if let id = record.postId, id > 0 {
                Text(verbatim: "No.\(id)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(XDTheme.secondaryText)
            } else if record.kind == .reply, let main = record.mainPostId, main > 0 {
                Text(verbatim: "回复至 No.\(main)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(XDTheme.secondaryText)
            } else {
                Text("串号未返回")
                    .font(.system(size: 11))
                    .foregroundStyle(XDTheme.secondaryText)
            }
        case .resultUnknown:
            Text("发送结果未知")
                .font(.system(size: 11))
                .foregroundStyle(XDTheme.admin)
        case .legacy:
            Text(verbatim: record.postId.map { "No.\($0) · 旧版推断" } ?? "编号未确认")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(XDTheme.secondaryText)
        }
    }

    private var postList: some View {
        Group {
            if filteredPosts.isEmpty && trimmedQuery.isEmpty {
                EmptyStateView(icon: segment == 1 ? "square.and.pencil" : "arrowshape.turn.up.left",
                               title: "还没有\(segmentName)记录")
                Spacer()
            } else if filteredPosts.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "没有匹配的记录")
                Spacer()
            } else {
                List {
                    ForEach(filteredPosts) { record in
                        Button {
                            openPost(record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    XDBadge(text: record.kind == .thread ? "发串" : "回复", color: XDTheme.link)
                                    postIdLabel(record)
                                    if record.hasImage {
                                        Image(systemName: "photo").font(.system(size: 10))
                                            .foregroundStyle(XDTheme.secondaryText)
                                    }
                                    Spacer()
                                    Text(RelativeTime.display(record.createdAt, relative: true))
                                        .font(.system(size: 11))
                                        .foregroundStyle(XDTheme.secondaryText)
                                }
                                if !record.title.isEmpty && record.title != "无标题" {
                                    Text(record.title).font(settings.titleFont)
                                }
                                Text(record.content)
                                    .font(.system(size: 13))
                                    .foregroundStyle(XDTheme.secondaryText)
                                    .lineLimit(4)
                            }
                            .padding(.vertical, 3)
                        }
                        .swipeActions {
                            Button {
                                copyToPasteboard(record.content)
                            } label: { Label("复制", systemImage: "doc.on.doc") }
                            .tint(.blue)
                            Button(role: .destructive) {
                                history.removePost(localId: record.id)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .confirmationDialog("编号未经确认",
                                    isPresented: Binding(get: { legacyThread != nil },
                                                         set: { if !$0 { legacyThread = nil } }),
                                    titleVisibility: .visible,
                                    presenting: legacyThread) { record in
                    Button {
                        if let pid = record.postId { app.openThread(pid) }
                    } label: {
                        Text(verbatim: "仍要打开 No.\(record.postId ?? 0)")
                    }
                    Button("取消", role: .cancel) {}
                } message: { _ in
                    Text("这个编号是旧版本在发送后推断的，可能不是这条发言。")
                }
            }
        }
    }
}

struct DraftsScreen: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var drafts = DraftStore.shared

    var body: some View {
        Group {
            if drafts.drafts.isEmpty {
                EmptyStateView(icon: "doc.text", title: "草稿箱是空的",
                               subtitle: "发串界面点「存草稿」即可保存。")
            } else {
                List {
                    ForEach(drafts.drafts) { draft in
                        Button {
                            app.compose = .draft(draft)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if !draft.title.isEmpty {
                                    Text(draft.title).font(.system(size: 15, weight: .medium))
                                }
                                Text(draft.preview)
                                    .font(.system(size: 13))
                                    .foregroundStyle(XDTheme.secondaryText)
                                    .lineLimit(3)
                                Text(RelativeTime.absolute(draft.updatedAt))
                                    .font(.system(size: 11))
                                    .foregroundStyle(XDTheme.secondaryText.opacity(0.8))
                            }
                        }
                    }
                    .onDelete { drafts.remove(at: $0) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("草稿箱")
        .navigationBarTitleDisplayMode(.inline)
    }
}
