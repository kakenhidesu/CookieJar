import SwiftUI

struct ForumPickerSheet: View {
    var onSelect: (Int, Bool) -> Void

    @EnvironmentObject private var forums: ForumStore
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredForums: [Forum] {
        guard !query.isEmpty else { return [] }
        return forums.visibleForums.filter {
            $0.showName.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty {
                    Section("搜索结果") {
                        ForEach(filteredForums) { forum in
                            row(name: forum.showName, id: forum.id, isTimeline: false)
                        }
                        if filteredForums.isEmpty {
                            Text("没有匹配的版块").foregroundStyle(XDTheme.secondaryText)
                        }
                    }
                } else {
                    if !forums.visibleTimelines.isEmpty {
                        Section("时间线") {
                            ForEach(forums.visibleTimelines) { t in
                                row(name: t.showName, id: t.id, isTimeline: true)
                            }
                        }
                    }
                    ForEach(forums.grouped(), id: \.0.id) { group, list in
                        Section(group.name) {
                            ForEach(list) { forum in
                                row(name: forum.showName, id: forum.id, isTimeline: false)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "搜索版块")
            .navigationTitle("版块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await forums.refresh() }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                        app.tab = .profile
                        app.profilePath.append(.forumManage)
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .overlay {
                if forums.isLoading && forums.forums.isEmpty {
                    ProgressView("正在获取版块列表…")
                }
            }
        }
    }

    private func row(name: String, id: Int, isTimeline: Bool) -> some View {
        Button {
            onSelect(id, isTimeline)
            Haptics.selection()
        } label: {
            HStack {
                Text(name)
                    .foregroundStyle(XDTheme.text)
                Spacer()
                if app.currentForumId == id && app.currentIsTimeline == isTimeline {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

struct ForumManageScreen: View {
    @EnvironmentObject private var forums: ForumStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var ordered: [Forum] = []

    var body: some View {
        List {
            Section {
                Picker("启动时打开", selection: Binding(
                    get: { "\(settings.defaultIsTimeline ? "t" : "f")\(settings.defaultForumId)" },
                    set: { value in
                        settings.defaultIsTimeline = value.hasPrefix("t")
                        settings.defaultForumId = Int(value.dropFirst()) ?? -1
                    })) {
                        ForEach(forums.visibleTimelines) { t in
                            Text(t.showName).tag("t\(t.id)")
                        }
                        ForEach(forums.visibleForums) { f in
                            Text(f.showName).tag("f\(f.id)")
                        }
                    }
            } footer: {
                Text("下次启动 App 时默认进入该版块。")
            }

            Section("拖动排序 / 左滑隐藏") {
                ForEach(ordered) { forum in
                    HStack {
                        Text(forum.showName)
                        Spacer()
                        if forums.isHidden(forum.id) {
                            Image(systemName: "eye.slash").foregroundStyle(XDTheme.secondaryText)
                        }
                    }
                    .swipeActions {
                        Button {
                            forums.toggleHidden(forum.id)
                        } label: {
                            Label(forums.isHidden(forum.id) ? "显示" : "隐藏",
                                  systemImage: forums.isHidden(forum.id) ? "eye" : "eye.slash")
                        }
                        .tint(.orange)
                    }
                }
                .onMove { source, destination in
                    ordered.move(fromOffsets: source, toOffset: destination)
                    forums.order = ordered.map(\.id)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("版块管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let rank = Dictionary(forums.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            ordered = forums.forums.sorted { a, b in
                let ra = rank[a.id] ?? (10_000 + a.sort)
                let rb = rank[b.id] ?? (10_000 + b.sort)
                return ra < rb
            }
        }
    }
}
