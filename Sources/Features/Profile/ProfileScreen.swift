import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var cookies: CookieStore
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var drafts = DraftStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var notices = NoticeStore.shared
    @State private var showNotice = false

    var body: some View {
        List {
            Section {
                Button {
                    app.push(.cookies)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(settings.accent.color.opacity(0.15))
                                .frame(width: 46, height: 46)
                            Image(systemName: "person.text.rectangle")
                                .foregroundStyle(settings.accent.color)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cookies.selected?.name ?? "未添加饼干")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(XDTheme.text)
                            Text(cookies.hasCookie ? "当前使用中，点击管理饼干" : "点击添加饼干后才能发串")
                                .font(.system(size: 12))
                                .foregroundStyle(XDTheme.secondaryText)
                        }
                        Spacer()
                        Text("\(cookies.cookies.count) 个")
                            .font(.system(size: 13))
                            .foregroundStyle(XDTheme.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(XDTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                row("草稿箱", icon: "doc.text", count: drafts.drafts.count) { app.push(.drafts) }
                row("发串记录", icon: "square.and.pencil", count: history.posts.count) {
                    app.tab = .history
                }
                row("黑名单", icon: "hand.raised", count: nil) { app.push(.blacklist) }
            }

            Section {
                Button {
                    showNotice = true
                } label: {
                    HStack {
                        Label("X 岛公告", systemImage: "megaphone")
                            .foregroundStyle(XDTheme.text)
                        Spacer()
                        if notices.shouldShow && notices.hasContent {
                            Circle().fill(XDTheme.admin).frame(width: 8, height: 8)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(XDTheme.secondaryText)
                    }
                }
                row("版块管理", icon: "square.grid.2x2", count: nil) { app.push(.forumManage) }
                row("设置", icon: "gearshape", count: nil) { app.push(.settings) }
                row("关于", icon: "info.circle", count: nil) { app.push(.about) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(XDTheme.background)
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNotice) {
            NoticeSheet(refreshOnAppear: true)
                .presentationDetents([.medium, .large])
        }
    }

    private func row(_ title: String, icon: String, count: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(XDTheme.text)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 13))
                        .foregroundStyle(XDTheme.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(XDTheme.secondaryText)
            }
        }
    }
}

struct AboutScreen: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image("AppIconImage")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("CookieJar")
                        .font(.system(size: 18, weight: .semibold))
                    Text("版本 \(AppInfo.version)")
                        .font(.system(size: 12))
                        .foregroundStyle(XDTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section("说明") {
                Text("CookieJar，一个基于 SwiftUI 的第三方 X 岛客户端")
                    .font(.system(size: 14))
            }

            Section {
                NavigationLink("诊断信息") {
                    DiagnosticsScreen()
                }
            }

            Section("致谢") {
                Link("orzogc/xdnmb_api", destination: URL(string: "https://github.com/orzogc/xdnmb_api")!)
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DiagnosticsScreen: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "（暂无记录）" : text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .background(XDTheme.background)
        .navigationTitle("诊断信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    copyToPasteboard(text, message: "已复制诊断信息")
                } label: { Image(systemName: "doc.on.doc") }
            }
        }
        .task { text = LaunchLog.report() }
    }
}
