import SwiftUI

struct NoticeSheet: View {
    var refreshOnAppear = false

    @ObservedObject private var store = NoticeStore.shared
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let notice = store.notice, !notice.content.isEmpty {
                        XDRichText(paragraphs: XDContent.parse(notice.content, revealHidden: true).paragraphs,
                                   font: settings.contentFont,
                                   lineSpacing: settings.lineSpacing)
                    } else if store.isLoading {
                        InlineLoading(text: "正在获取公告…")
                    } else {
                        EmptyStateView(icon: "megaphone", title: "暂时没有公告")
                    }
                }
                .padding(16)
            }
            .background(XDTheme.background)
            .navigationTitle(store.notice.map { $0.day.isEmpty ? "公告" : "公告 \($0.day)" } ?? "公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("知道了") {
                        store.markSeen()
                        dismiss()
                    }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let id = XDContent.postId(fromRefURL: url) else { return .systemAction }
            store.markSeen()
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                app.referencePostId = id
            }
            return .handled
        })
        .task {
            if refreshOnAppear { await store.refresh() }
        }
    }
}
