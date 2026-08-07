import SwiftUI

struct HistoryScreen: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var history = HistoryStore.shared
    @State private var segment = 0

    private var segmentName: String {
        switch segment {
        case 0: return "浏览"
        case 1: return "发串"
        default: return "回复"
        }
    }
    @State private var showClearConfirm = false
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredBrowsing: [(day: Date, records: [BrowseRecord])] {
        let q = trimmedQuery
        guard !q.isEmpty else { return history.browsingByDay }
        let cal = Calendar.current
        let matched = history.browsing.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.preview.localizedCaseInsensitiveContains(q)
                || $0.userHash.localizedCaseInsensitiveContains(q)
                || "\($0.id)".contains(q)
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
                || "\($0.id)".contains(q)
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

                if segment == 0 { browsingList } else { postList }
            }
        }
        .navigationTitle("历史")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "搜索\(segmentName)记录")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: { Image(systemName: "trash") }
            }
        }
        .confirmationDialog("确定要清空吗？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空\(segmentName)记录", role: .destructive) {
                if segment == 0 { history.clearBrowsing() } else { history.clearPosts() }
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
                EmptyStateView(icon: "magnifyingglass", title: "没有匹配的记录")
                Spacer()
            } else {
                List {
                    ForEach(filteredBrowsing, id: \.day) { day, records in
                        Section(RelativeTime.day(day)) {
                            ForEach(records) { record in
                                Button {
                                    app.openThread(record.id, page: record.lastPage, jumpTo: record.lastPostId)
                                } label: {
                                    recordRow(record)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        history.removeBrowse(id: record.id)
                                    } label: { Label("删除", systemImage: "trash") }
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
        HStack(alignment: .top, spacing: 10) {
            if !record.image.isEmpty && settings.showImages {
                AsyncThumb(file: record.image + record.imageExtension,
                           width: 56, height: 56, cornerRadius: 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title == "无标题" ? "No.\(record.id)" : record.title)
                    .font(settings.titleFont)
                    .foregroundStyle(XDTheme.text)
                    .lineLimit(1)
                Text(record.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(XDTheme.secondaryText)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(record.userHash)
                        .font(.system(size: 11, design: .monospaced))
                    Text("第 \(record.lastPage) 页")
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
                            let target = record.kind == .thread ? record.id : (record.mainPostId ?? record.id)
                            if target > 0 { app.openThread(target) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    XDBadge(text: record.kind == .thread ? "发串" : "回复", color: XDTheme.link)
                                    if record.id > 0 {
                                        Text(verbatim: "No.\(record.id)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(XDTheme.secondaryText)
                                    }
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
                                history.removePost(id: record.id)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
