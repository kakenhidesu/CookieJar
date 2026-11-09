import SwiftUI

struct HighlightedSearchText: View {
    let text: String
    let query: String
    @EnvironmentObject private var settings: SettingsStore

    var body: some View { Text(highlighted) }

    private var highlighted: AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive],
                                     range: start..<text.endIndex), range.upperBound > start {
            if let lower = AttributedString.Index(range.lowerBound, within: result),
               let upper = AttributedString.Index(range.upperBound, within: result) {
                result[lower..<upper].foregroundColor = settings.accent.color
                result[lower..<upper].font = .system(size: 13, weight: .semibold)
            }
            start = range.upperBound
        }
        return result
    }
}

struct SearchHitRow: View {
    let hit: ReadingSearchStore.Hit
    let threadId: Int
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(hit.postId == threadId ? "主串" : "No.\(hit.postId)")
                Spacer()
                Text(hit.onlyPo ? "只看 Po · 第 \(hit.page) 页" : "第 \(hit.page) 页")
            }
            .font(.caption)
            .foregroundStyle(XDTheme.secondaryText)
            HighlightedSearchText(text: hit.excerpt, query: query)
                .font(.system(size: 13))
                .foregroundStyle(XDTheme.text)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct ThreadSearchBar: View {
    let threadId: Int
    let loadedRows: [ReadingSearchStore.BackupRow]
    let isPositioning: Bool
    var onSelect: (ReadingSearchStore.Hit) -> Void
    var onClose: () -> Void
    @ObservedObject private var store = ReadingSearchStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var blacklist = BlacklistStore.shared
    @State private var query = ""
    @State private var hits: [ReadingSearchStore.Hit] = []
    @State private var selectedID: Int?
    @State private var showMatches = false
    @State private var isSearching = false
    @State private var error: String?
    @State private var completedRequest: Request?
    @State private var retry = 0
    @FocusState private var focused: Bool

    private struct Request: Equatable {
        var query: String
        var revision: Int
        var blacklist: BlacklistStore.Payload
        var rows: [ReadingSearchStore.BackupRow]
        var retry: Int
    }

    private var request: Request {
        Request(query: query.trimmingCharacters(in: .whitespacesAndNewlines), revision: store.revision,
                blacklist: blacklist.data, rows: loadedRows, retry: retry)
    }
    private var currentHits: [ReadingSearchStore.Hit] { completedRequest == request ? hits : [] }
    private var selectedIndex: Int? { currentHits.firstIndex { $0.postId == selectedID } }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(XDTheme.secondaryText)
                TextField("查找本串已加载内容", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { select(at: 0) }
                if isSearching { ProgressView().controlSize(.mini) }
                Button(action: onClose) { Image(systemName: "xmark") }
                    .accessibilityLabel("关闭串内查找")
            }
            if !request.query.isEmpty {
                HStack {
                    Button {
                        showMatches.toggle()
                        focused = false
                    } label: {
                        Text(selectedIndex.map { "\($0 + 1) / \(currentHits.count)" }
                             ?? "\(currentHits.count) 条匹配")
                            .monospacedDigit()
                        Image(systemName: showMatches ? "chevron.up" : "chevron.down")
                    }
                    .disabled(currentHits.isEmpty)
                    Spacer()
                    Button { select(at: (selectedIndex ?? 0) - 1) } label: {
                        Label("上一条", systemImage: "arrow.up")
                    }
                    .disabled(isPositioning || (selectedIndex ?? 0) == 0)
                    Button { select(at: selectedIndex.map { $0 + 1 } ?? 0) } label: {
                        Label("下一条", systemImage: "arrow.down")
                    }
                    .disabled(isPositioning || currentHits.isEmpty || selectedIndex == currentHits.count - 1)
                }
                .font(.caption)
                if let error {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(XDTheme.secondaryText)
                        Button("重试") { retry += 1 }.font(.caption)
                    }
                }
                if showMatches && !currentHits.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(currentHits.enumerated()), id: \.element.id) { index, hit in
                                Button { select(at: index) } label: {
                                    SearchHitRow(hit: hit, threadId: threadId, query: request.query)
                                }
                                .buttonStyle(.plain)
                                .disabled(isPositioning)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(XDTheme.background)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { focused = true }
        .task(id: request) { await search() }
    }

    private func select(at index: Int) {
        guard !isPositioning, currentHits.indices.contains(index) else { return }
        let hit = currentHits[index]
        selectedID = hit.postId
        focused = false
        showMatches = false
        onSelect(hit)
    }

    @MainActor
    private func search() async {
        let target = request
        error = nil
        if completedRequest?.query != target.query { selectedID = nil }
        guard !target.query.isEmpty else {
            hits = []
            completedRequest = target
            isSearching = false
            return
        }
        isSearching = true
        defer { if !Task.isCancelled && request == target { isSearching = false } }
        var matches: [ReadingSearchStore.Hit] = []
        var failure: String?
        do {
            try await Task.sleep(nanoseconds: 200_000_000)
            let result = try await store.search(target.query, blacklist: target.blacklist,
                                                browsing: history.browsing, threadId: threadId,
                                                loadedRows: target.rows)
            matches = result.matches[threadId]?.hits ?? []
        } catch {
            failure = error.localizedDescription
        }
        guard !Task.isCancelled, request == target else { return }
        hits = matches
        completedRequest = target
        error = failure
        if failure == nil && !hits.contains(where: { $0.postId == selectedID }) { selectedID = nil }
    }
}

struct ThreadImageItem: Identifiable {
    var id: Int
    var file: String
    var page: Int
    var onlyPo: Bool
}

struct ThreadImageGallery: View {
    let threadId: Int
    let items: [ThreadImageItem]
    var onLocate: (ThreadImageItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var viewer: ImageViewerPayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    EmptyStateView(icon: "photo.on.rectangle", title: "已加载内容中没有图片")
                        .padding(.top, 32)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 6) {
                                AsyncThumb(file: item.file, height: 110, cornerRadius: 8, onTap: { _ in
                                    viewer = ImageViewerPayload(images: items.map { XDURLs.shared.image($0.file) }, index: index)
                                })
                                Button {
                                    onLocate(item)
                                    dismiss()
                                } label: {
                                    Label(item.id == threadId ? "定位主串" : "No.\(item.id)", systemImage: "arrow.up.forward.app")
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .background(XDTheme.background)
            .navigationTitle("图片总览 · \(items.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fullScreenCover(item: $viewer) { ImageViewerScreen(payload: $0) }
        }
    }
}
