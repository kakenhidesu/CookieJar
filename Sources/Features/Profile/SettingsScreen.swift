import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var cacheSize: String = "计算中…"
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题色", selection: $settings.accentRaw) {
                    ForEach(XDTheme.Accent.allCases) { accent in
                        HStack {
                            Circle().fill(accent.color).frame(width: 14, height: 14)
                            Text(accent.rawValue)
                        }
                        .tag(accent.rawValue)
                    }
                }
                Picker("深色模式", selection: $settings.appearanceRaw) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("正文字号")
                        Spacer()
                        Text(String(format: "%.0f%%", settings.fontScale * 100))
                            .foregroundStyle(XDTheme.secondaryText)
                    }
                    Slider(value: $settings.fontScale, in: 0.8...1.6, step: 0.05)
                    Text("示例：( ﾟ∀。)7 这是一段正文预览")
                        .font(.system(size: 16 * settings.fontScale))
                        .lineSpacing(settings.lineSpacing)
                        .foregroundStyle(XDTheme.secondaryText)
                }
                VStack(alignment: .leading) {
                    Text("行间距 \(Int(settings.lineSpacing))")
                    Slider(value: $settings.lineSpacing, in: 0...12, step: 1)
                }
                Toggle("紧凑卡片（不显示最近回复）", isOn: $settings.compactCard)
                Toggle("显示图片", isOn: $settings.showImages)
            }

            Section("阅读") {
                Toggle("记录浏览历史", isOn: $settings.recordBrowsing)
                Toggle("记住阅读进度", isOn: $settings.restoreReadProgress)
                Toggle("启动时回到上次的串", isOn: $settings.restoreLastThread)
                Toggle("显示相对时间", isOn: $settings.showRelativeTime)
                Toggle("自动展开隐藏内容", isOn: $settings.autoRevealHidden)
            }

            Section("发串") {
                Toggle("默认加水印", isOn: $settings.watermark)
                Toggle("关闭时自动存草稿", isOn: $settings.saveDraftAuto)
                TextField("默认名称", text: $settings.defaultName)
                TextField("默认标题", text: $settings.defaultTitle)
                VStack(alignment: .leading) {
                    Text("图片压缩质量 \(String(format: "%.0f%%", settings.imageQuality * 100))")
                    Slider(value: $settings.imageQuality, in: 0.3...1.0, step: 0.05)
                }
            }

            Section {
                Picker("订阅排序", selection: $settings.feedSortRaw) {
                    ForEach(FeedSort.allCases) { sort in
                        Text(sort.label).tag(sort.rawValue)
                    }
                }
                Toggle("使用网页版订阅", isOn: $settings.useHTMLFeed)
                HStack {
                    Text("订阅 ID")
                    Spacer()
                    Text(settings.feedUUID.prefix(13) + "…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(XDTheme.secondaryText)
                }
                Button("复制订阅 ID") {
                    copyToPasteboard(settings.feedUUID, message: "已复制订阅 ID")
                }
                Button("从剪贴板导入订阅 ID") {
                    if let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       s.count >= 8 {
                        settings.feedUUID = s
                        Toast.shared.success("已导入订阅 ID")
                    } else {
                        Toast.shared.error("剪贴板里没有有效的订阅 ID")
                    }
                }
            } header: {
                Text("订阅")
            } footer: {
                Text("订阅排序只作用于已经加载出来的订阅。订阅 ID 相当于你的订阅账号，在其它设备上填入相同的 ID 就能同步订阅列表；网页版订阅则跟随饼干。")
            }

            Section {
                Toggle("使用备用 API", isOn: $settings.useBackupAPI)
                Toggle("启动时更新域名", isOn: $settings.updateEndpointsOnLaunch)
                Stepper("连接超时 \(settings.timeout) 秒", value: $settings.timeout, in: 5...60, step: 5)
                Button("立即更新域名 / CDN") {
                    Task {
                        await XDAPI.shared.refreshEndpoints()
                        Toast.shared.success("已更新")
                    }
                }
            } header: {
                Text("网络")
            } footer: {
                Text("X 岛主域名会不定期更换，开启「启动时更新域名」可自动跟随。")
            }

            Section("存储") {
                HStack {
                    Text("图片缓存")
                    Spacer()
                    Text(cacheSize).foregroundStyle(XDTheme.secondaryText)
                }
                Button("清空图片缓存") {
                    Task {
                        await ImageCache.shared.clearDisk()
                        await updateCacheSize()
                        Toast.shared.success("已清空图片缓存")
                    }
                }
                Button("清空阅读进度") {
                    HistoryStore.shared.clearProgress()
                    Toast.shared.show("已清空")
                }
                Button("恢复默认设置", role: .destructive) { showResetConfirm = true }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { await updateCacheSize() }
        .onChange(of: settings.useBackupAPI) { _ in settings.applyToNetwork() }
        .onChange(of: settings.timeout) { _ in settings.applyToNetwork() }
        .confirmationDialog("确定恢复默认设置？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) { reset() }
            Button("取消", role: .cancel) {}
        }
    }

    private func updateCacheSize() async {
        let bytes = await ImageCache.shared.diskSize()
        cacheSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func reset() {
        settings.accentRaw = XDTheme.Accent.purple.rawValue
        settings.appearanceRaw = "system"
        settings.fontScale = 1.0
        settings.lineSpacing = 4
        settings.compactCard = false
        settings.showImages = true
        settings.recordBrowsing = true
        settings.restoreReadProgress = true
        settings.showRelativeTime = true
        settings.autoRevealHidden = false
        settings.watermark = false
        settings.saveDraftAuto = true
        settings.imageQuality = 0.8
        settings.useHTMLFeed = false
        settings.feedSortRaw = FeedSort.default.rawValue
        settings.useBackupAPI = false
        settings.timeout = 20
        settings.applyToNetwork()
        Toast.shared.success("已恢复默认设置")
    }
}

struct BlacklistScreen: View {
    @ObservedObject private var blacklist = BlacklistStore.shared
    @EnvironmentObject private var forums: ForumStore
    @State private var newKeyword = ""

    var body: some View {
        List {
            Section("屏蔽关键词") {
                HStack {
                    TextField("添加关键词", text: $newKeyword)
                    Button("添加") {
                        blacklist.addKeyword(newKeyword)
                        newKeyword = ""
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(blacklist.data.keywords, id: \.self) { word in
                    Text(word)
                        .swipeActions {
                            Button(role: .destructive) { blacklist.removeKeyword(word) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }

            Section("屏蔽的饼干") {
                if blacklist.data.users.isEmpty {
                    Text("暂无").foregroundStyle(XDTheme.secondaryText)
                }
                ForEach(blacklist.data.users.keys.sorted(), id: \.self) { hash in
                    HStack {
                        Text(hash).font(.system(size: 14, design: .monospaced))
                        Spacer()
                        Button("解除") { blacklist.unblock(user: hash) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 13))
                    }
                }
            }

            Section("屏蔽的串") {
                if blacklist.data.posts.isEmpty {
                    Text("暂无").foregroundStyle(XDTheme.secondaryText)
                }
                ForEach(blacklist.data.posts.keys.sorted(), id: \.self) { id in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(verbatim: "No.\(id)").font(.system(size: 14, design: .monospaced))
                            if let t = blacklist.data.posts[id], !t.isEmpty, t != "无标题" {
                                Text(t).font(.system(size: 12)).foregroundStyle(XDTheme.secondaryText)
                            }
                        }
                        Spacer()
                        Button("解除") { blacklist.unblock(post: id) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 13))
                    }
                }
            }

            Section("屏蔽的版块") {
                ForEach(forums.forums) { forum in
                    Toggle(forum.showName, isOn: Binding(
                        get: { blacklist.isBlocked(forum: forum.id) },
                        set: { _ in blacklist.toggle(forum: forum.id) }))
                }
            }

            Section {
                Button("清空黑名单", role: .destructive) {
                    blacklist.clearAll()
                    Toast.shared.show("已清空")
                }
            }
        }
        .navigationTitle("黑名单")
        .navigationBarTitleDisplayMode(.inline)
    }
}
