import SwiftUI

struct PostBodyView: View {
    let post: XDPost
    var isPo: Bool = false
    var poHash: String?
    var lineLimit: Int?
    var showForum: Bool = false
    var showReplyCount: Bool = false
    var showPostId: Bool = true
    var onTapImage: ((URL) -> Void)?

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var forums: ForumStore
    @ObservedObject private var cookies = CookieStore.shared
    @State private var revealHidden = false

    private var parsed: XDContent.Result {
        XDContent.parse(post.content, revealHidden: revealHidden || settings.autoRevealHidden)
    }

    var body: some View {
        let result = parsed

        VStack(alignment: .leading, spacing: 8) {
            header

            if post.title != "无标题" && !post.title.isEmpty {
                Text(post.title)
                    .font(settings.titleFont)
                    .foregroundStyle(post.kind == .tip ? XDTheme.admin : XDTheme.text)
            }
            if post.name != "无名氏" && !post.name.isEmpty {
                Text(post.name)
                    .font(settings.metaFont)
                    .foregroundStyle(XDTheme.secondaryText)
            }

            if post.isSage {
                Text("本串已经被SAGE")
                    .font(settings.metaFont)
                    .foregroundStyle(XDTheme.admin)
            }

            if !result.plain.isEmpty {
                Text(result.text)
                    .font(settings.contentFont)
                    .foregroundStyle(XDTheme.text)
                    .lineSpacing(settings.lineSpacing)
                    .textSelection(.enabled)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if result.hasHidden && !settings.autoRevealHidden {
                Button {
                    withAnimation { revealHidden.toggle() }
                    Haptics.light()
                } label: {
                    Label(revealHidden ? "折叠隐藏内容" : "显示隐藏内容",
                          systemImage: revealHidden ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }

            if let file = post.imageFile, settings.showImages {
                AsyncThumb(file: file, onTap: onTapImage)
            }

            if showReplyCount, let count = post.replyCount, count > 0 {
                Text("\(count) 回应")
                    .font(settings.metaFont)
                    .foregroundStyle(XDTheme.secondaryText)
            }
        }
    }

    private var isSelf: Bool {
        cookies.isMine(displayId: post.userHash) || HistoryStore.shared.isMyPost(id: post.id)
    }

    private var isPoPost: Bool {
        isPo || (poHash != nil && post.userHash == poHash)
    }

    private var hashColor: Color {
        if post.kind == .tip || post.isAdmin { return XDTheme.admin }
        if isSelf { return XDTheme.selfHash }
        if isPoPost { return XDTheme.poBadge }
        return XDTheme.secondaryText
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(post.userHash)
                .font(.system(size: 12.5 * settings.fontScale, weight: .medium, design: .monospaced))
                .foregroundStyle(hashColor)
                .lineLimit(1)

            if isSelf {
                XDBadge(text: "我", color: XDTheme.selfHash)
            }
            if isPoPost {
                XDBadge(text: "Po", color: XDTheme.poBadge)
            }
            if showForum, let fid = post.forumId, fid > 0 {
                XDBadge(text: forums.name(forId: fid), color: XDTheme.link)
            }

            Spacer(minLength: 4)

            Text(post.kind == .tip
                 ? RelativeTime.full(post.postTime)
                 : RelativeTime.display(post.postTime, relative: settings.showRelativeTime))
                .font(settings.metaFont)
                .foregroundStyle(XDTheme.secondaryText)

            if showPostId {
                Text(verbatim: "No.\(post.id)")
                    .font(.system(size: 11.5 * settings.fontScale, design: .monospaced))
                    .foregroundStyle(XDTheme.secondaryText.opacity(0.8))
            }
        }
    }
}

struct AsyncThumb: View {
    let file: String
    var width: CGFloat?
    var height: CGFloat = 170
    var cornerRadius: CGFloat = 10
    var onTap: ((URL) -> Void)?

    var body: some View {
        Color.clear
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
            .overlay(image)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if GIF.isGIF(file) { badge }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let onTap else { return }
                onTap(XDURLs.shared.image(file))
                Haptics.light()
            }
    }

    @ViewBuilder
    private var image: some View {
        if GIF.isGIF(file) {
            XDGIFImage(primary: XDURLs.shared.thumb(file),
                       fallback: XDURLs.shared.image(file),
                       maxPixel: min(height * 3, 360))
        } else {
            XDAsyncImage(url: XDURLs.shared.thumb(file), contentMode: .fill)
        }
    }

    private var badge: some View {
        Text(verbatim: "GIF")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(4)
    }
}

struct ThreadCardView: View {
    let item: ForumThread
    var showForum: Bool = true

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var subscriptions = SubscriptionCache.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostBodyView(post: item.mainPost,
                         isPo: true,
                         lineLimit: settings.compactCard ? 4 : 10,
                         showForum: showForum,
                         showPostId: false,
                         onTapImage: { url in
                             app.imageViewer = ImageViewerPayload(images: [url], index: 0)
                         })

            if !item.recentReplies.isEmpty && !settings.compactCard {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.recentReplies.prefix(3)) { reply in
                        HStack(alignment: .top, spacing: 6) {
                            Rectangle()
                                .fill(XDTheme.hairline)
                                .frame(width: 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reply.userHash)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(reply.userHash == item.mainPost.userHash ? XDTheme.poBadge : XDTheme.secondaryText)
                                Text(reply.preview)
                                    .font(.system(size: 13 * settings.fontScale))
                                    .foregroundStyle(XDTheme.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(.leading, 2)
            }

            HStack(spacing: 10) {
                Label(String(item.mainPost.replyCount ?? 0), systemImage: "bubble.left")
                if let remain = item.remainReplies, remain > 0 {
                    Text(verbatim: "剩余 \(remain)")
                }
                Text(verbatim: "最后回复于 \(RelativeTime.hourMinute(item.lastReplyTime))")
                    .lineLimit(1)
                Spacer()
                Button {
                    let id = item.mainPost.id
                    let subscribed = subscriptions.contains(id)
                    Task {
                        do {
                            if subscribed {
                                try await FeedService.shared.unsubscribe(mainPostId: id)
                                Toast.shared.success("已取消订阅")
                            } else {
                                try await FeedService.shared.subscribe(mainPostId: id)
                                Toast.shared.success("订阅成功")
                            }
                        } catch {
                            Toast.shared.error(error)
                        }
                    }
                    Haptics.light()
                } label: {
                    Image(systemName: subscriptions.contains(item.mainPost.id) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.borderless)

                Text(verbatim: "No.\(item.mainPost.id)")
                    .font(.system(size: 11.5 * settings.fontScale, design: .monospaced))
                    .foregroundStyle(XDTheme.secondaryText.opacity(0.8))
            }
            .font(settings.metaFont)
            .foregroundStyle(XDTheme.secondaryText)
        }
        .xdCard()
        .contentShape(Rectangle())
    }
}

@ViewBuilder
func postCommonMenuItems(_ post: XDPost) -> some View {
    Button {
        copyToPasteboard(XDContent.plainText(post.content), message: "已复制内容")
    } label: { Label("复制内容", systemImage: "doc.on.doc") }

    Button {
        copyToPasteboard("No.\(post.id)", message: "已复制串号")
    } label: { Label("复制串号", systemImage: "number") }

    Button {
        copyToPasteboard(XDURLs.shared.webThreadURL(post.mainPostId ?? post.id).absoluteString,
                         message: "已复制链接")
    } label: { Label("复制链接", systemImage: "link") }

    Divider()

    Button {
        guard CookieStore.shared.hasCookie else {
            Toast.shared.error("举报需要先添加饼干")
            return
        }
        AppState.shared.compose = .report(postId: post.id)
    } label: { Label("举报", systemImage: "exclamationmark.bubble") }

    Button(role: .destructive) {
        BlacklistStore.shared.block(user: post.userHash)
        Toast.shared.show("已屏蔽饼干 \(post.userHash)")
    } label: { Label("屏蔽该饼干", systemImage: "person.slash") }
}
