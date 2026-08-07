import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var notices = NoticeStore.shared

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { app.tab },
            set: { newTab in
                if newTab == app.tab {
                    app.reselect(newTab)
                } else {
                    app.tab = newTab
                    LaunchLog.mark("切换到 \(newTab)")
                }
            }
        )
    }

    var body: some View {
        ZStack {
            TabView(selection: tabSelection) {
                stack(path: $app.forumsPath) { ForumThreadsScreen() }
                    .tabItem { Label("版块", systemImage: "square.grid.2x2") }
                    .tag(AppTab.forums)

                stack(path: $app.feedPath) { FeedScreen() }
                    .tabItem { Label("订阅", systemImage: "bookmark") }
                    .tag(AppTab.feed)

                stack(path: $app.historyPath) { HistoryScreen() }
                    .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
                    .tag(AppTab.history)

                stack(path: $app.profilePath) { ProfileScreen() }
                    .tabItem { Label("我的", systemImage: "person.crop.circle") }
                    .tag(AppTab.profile)
            }

            ToastOverlay()
        }
        .sheet(item: $app.compose) { target in
            ComposeScreen(target: target)
        }
        .sheet(isPresented: Binding(get: { app.referencePostId != nil },
                                    set: { if !$0 { app.referencePostId = nil } })) {
            if let id = app.referencePostId {
                ReferenceSheet(postId: id)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(item: $app.imageViewer) { payload in
            ImageViewerScreen(payload: payload)
        }
        .sheet(isPresented: Binding(
            get: { notices.shouldShow && notices.hasContent },
            set: { if !$0 { notices.markSeen() } }
        )) {
            NoticeSheet()
                .presentationDetents([.medium, .large])
        }
        .environment(\.openURL, OpenURLAction { url in
            if AppState.shared.handle(url: url) { return .handled }
            return .systemAction
        })
    }

    @ViewBuilder
    private func stack<Content: View>(path: Binding<[AppRoute]>, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                }
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .forum(let id, let isTimeline):
            ForumThreadsScreen(forumId: id, isTimeline: isTimeline)
        case .thread(let id, let page, let onlyPo, let jumpTo):
            ThreadScreen(mainPostId: id, initialPage: page, onlyPo: onlyPo, jumpToPostId: jumpTo)
        case .searchResult(let query):
            SearchScreen(initialQuery: query)
        case .drafts:
            DraftsScreen()
        case .blacklist:
            BlacklistScreen()
        case .cookies:
            CookieScreen()
        case .settings:
            SettingsScreen()
        case .forumManage:
            ForumManageScreen()
        case .about:
            AboutScreen()
        }
    }
}
