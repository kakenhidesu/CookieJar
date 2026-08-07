import SwiftUI
import UIKit

@main
struct CookieJarApp: App {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var app = AppState.shared
    @StateObject private var forums = ForumStore.shared
    @StateObject private var cookies = CookieStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchLog.startNewRun()
        LaunchLog.mark("app init（内存 \(LaunchLog.footprintMB)MB）")

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            LaunchLog.mark("收到内存警告，占用 \(LaunchLog.footprintMB)MB")
            Task { await ImageCache.shared.dropMemory() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(app)
                .environmentObject(forums)
                .environmentObject(cookies)
                .tint(settings.accent.color)
                .preferredColorScheme(settings.colorScheme)
                .task { await bootstrap() }
                .onOpenURL { url in _ = app.handle(url: url) }
        }
        .onChange(of: scenePhase) { phase in
            LaunchLog.mark("scenePhase \(phase)（Tab \(app.tab)，内存 \(LaunchLog.footprintMB)MB）")
            guard phase == .background else { return }
            HistoryStore.shared.flush()
            Task {
                await ImageCache.shared.dropMemory()
                LaunchLog.mark("已释放图片内存，剩 \(LaunchLog.footprintMB)MB")
            }
        }
    }

    @State private var didBootstrap = false

    private func bootstrap() async {
        guard !didBootstrap else {
            LaunchLog.mark("bootstrap 重复触发，已跳过")
            return
        }
        didBootstrap = true

        LaunchLog.mark("bootstrap start（饼干 \(cookies.hasCookie ? "有" : "无")）")
        settings.applyToNetwork()

        if let session = HistoryStore.shared.lastSession, app.restoreLastThreadIfNeeded() {
            LaunchLog.mark("恢复到上次的串 No.\(session.mainPostId) 第 \(session.page) 页")
        }

        if settings.updateEndpointsOnLaunch {
            Task.detached(priority: .utility) {
                LaunchLog.mark("refreshEndpoints begin")
                await XDAPI.shared.refreshEndpoints()
                LaunchLog.mark("refreshEndpoints done base=\(XDURLs.shared.base.host ?? "?")")
            }
        }

        Task { await NoticeStore.shared.refresh() }

        if forums.forums.isEmpty {
            LaunchLog.mark("forum list begin（无缓存）")
            await forums.refresh()
        } else {
            LaunchLog.mark("forum list begin（有缓存 \(forums.forums.count) 个）")
            Task { await forums.refresh() }
        }
        LaunchLog.mark("bootstrap done")
    }
}
