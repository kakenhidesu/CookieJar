import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var notices = NoticeStore.shared
    @ObservedObject private var unread = FeedUnreadStore.shared
    @ObservedObject private var feed = FeedViewModel.shared
    @Environment(\.colorScheme) private var colorScheme

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { app.tab },
            set: { newTab in
                if newTab == .forums {
                    Task { await CookieStore.shared.syncDisplayIds(force: true) }
                }
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
                    .tabItem {
                        Label {
                            Text("订阅")
                        } icon: {
                            Image(uiImage: feedTabIcon).renderingMode(.original)
                        }
                    }
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
        .disabled(feed.isRestoring)
        .task(id: settings.feedContextID) {
            await FeedViewModel.shared.refreshIfNeeded()
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

    private var feedTabIcon: UIImage {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let color = (app.tab == .feed ? UIColor(settings.accent.color) : UIColor.secondaryLabel)
            .resolvedColor(with: traits)
        guard let symbol = UIImage(systemName: "bookmark",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 24)) else {
            return UIImage()
        }
        // Keep identical geometry in both states; the dot must not move the bookmark.
        var icon = UIGraphicsImageRenderer(size: symbol.size).image { _ in
            symbol.withTintColor(color, renderingMode: .alwaysOriginal).draw(at: .zero)
            if unread.hasUnread {
                UIColor.systemRed.setFill()
                UIBezierPath(ovalIn: CGRect(x: symbol.size.width - 7, y: 0, width: 7, height: 7)).fill()
            }
        }.withAlignmentRectInsets(symbol.alignmentRectInsets)
        // Rasterizing an SF Symbol does not retain its baseline automatically.
        if let baseline = symbol.baselineOffsetFromBottom {
            icon = icon.withBaselineOffset(fromBottom: baseline)
        }
        return icon.withRenderingMode(.alwaysOriginal)
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
        case .backup:
            BackupScreen()
        }
    }
}
