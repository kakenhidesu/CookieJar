import SwiftUI
import PhotosUI
import UIKit

struct ComposeScreen: View {
    let target: ComposeTarget

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var cookies: CookieStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var name = ""
    @State private var content = ""
    @State private var image: UIImage?
    @State private var imageIsPNG = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showEmoticons = false
    @State private var showDoodle = false
    @State private var isSending = false
    @State private var draftId: UUID?
    @State private var showDrafts = false
    @State private var forumId: Int?
    @FocusState private var contentFocused: Bool

    @State private var reportReason = ""
    @State private var showCustomReason = false
    @State private var customReason = ""

    private var replyTarget: Int? {
        if case .reply(let mid, _) = target { return mid }
        return nil
    }

    private var isReport: Bool {
        if case .report = target { return true }
        return false
    }

    private var navTitle: String {
        if isReport { return "举报" }
        if let mid = replyTarget { return String(format: "回复 No.%d", mid) }
        return "发串"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                XDTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 12) {
                            reportBar
                            forumBar
                            cookieBar

                            VStack(spacing: 0) {
                                TextField("标题（可留空）", text: $title)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                Divider()
                                TextField("名称（可留空）", text: $name)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                            }
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(XDTheme.card))

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $content)
                                    .focused($contentFocused)
                                    .font(settings.contentFont)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 220)
                                    .padding(8)
                                if content.isEmpty {
                                    Text("说点什么…")
                                        .foregroundStyle(XDTheme.secondaryText.opacity(0.7))
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(XDTheme.card))

                            if let image {
                                imagePreview(image)
                            }
                        }
                        .padding(12)
                    }

                    toolbarBar
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { closeWithAutosave() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending { ProgressView() } else { Text("发送").bold() }
                    }
                    .disabled(isSending || (content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && image == nil))
                }
            }
            .sheet(isPresented: $showEmoticons) {
                EmoticonPickerView { text in
                    content += text
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDrafts) {
                DraftPickerSheet { draft in
                    saveDraft(explicit: false)
                    title = draft.title
                    name = draft.name
                    content = draft.content
                    draftId = draft.id
                    showDrafts = false
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showDoodle) {
                DoodleScreen { result in
                    image = result
                    imageIsPNG = true
                }
            }
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        image = ui
                        imageIsPNG = false
                    }
                }
            }
            .onAppear(perform: prefill)
        }
        .interactiveDismissDisabled(isSending)
    }

    @ViewBuilder
    private var reportBar: some View {
        if isReport {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble")
                    .foregroundStyle(XDTheme.secondaryText)
                Menu {
                    ForEach(ReportInfo.reasons, id: \.self) { reason in
                        Button {
                            reportReason = reason
                            Haptics.selection()
                        } label: {
                            if reportReason == reason {
                                Label(reason, systemImage: "checkmark")
                            } else {
                                Text(reason)
                            }
                        }
                    }
                    Divider()
                    Button("自定义理由…") { showCustomReason = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(reportReason.isEmpty ? "请选择举报理由" : reportReason)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(reportReason.isEmpty ? XDTheme.admin : XDTheme.text)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                }
                Spacer()
                Text("发往值班室")
                    .font(.system(size: 12))
                    .foregroundStyle(XDTheme.secondaryText)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(XDTheme.card))
            .alert("自定义举报理由", isPresented: $showCustomReason) {
                TextField("举报理由", text: $customReason)
                Button("确定") {
                    let r = customReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !r.isEmpty { reportReason = r }
                    customReason = ""
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var forumBar: some View {
        if replyTarget == nil && !isReport {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(XDTheme.secondaryText)
                Menu {
                    ForEach(ForumStore.shared.visibleForums) { forum in
                        Button {
                            forumId = forum.id
                            Haptics.selection()
                        } label: {
                            if forumId == forum.id {
                                Label(forum.showName, systemImage: "checkmark")
                            } else {
                                Text(forum.showName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(forumId.map { ForumStore.shared.name(forId: $0) } ?? "请选择版块")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(forumId == nil ? XDTheme.admin : XDTheme.text)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(XDTheme.card))
        }
    }

    private var cookieBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(XDTheme.secondaryText)
            Menu {
                ForEach(cookies.cookies) { c in
                    Button {
                        cookies.select(c)
                    } label: {
                        if cookies.selected?.userHash == c.userHash {
                            Label(c.name, systemImage: "checkmark")
                        } else {
                            Text(c.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(cookies.selected?.name ?? "未选择饼干")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
            }
            Spacer()
            Toggle(isOn: $settings.watermark) {
                Text("水印").font(.system(size: 13))
            }
            .toggleStyle(.switch)
            .labelsHidden()
            Text("水印").font(.system(size: 12)).foregroundStyle(XDTheme.secondaryText)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(XDTheme.card))
    }

    private func imagePreview(_ img: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                image = nil
                photoItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding(8)
        }
    }

    private var toolbarBar: some View {
        HStack(spacing: 20) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
            }
            Button { showDoodle = true } label: { Image(systemName: "scribble.variable") }
            Button { showEmoticons = true } label: { Image(systemName: "face.smiling") }
            Button { insertHiddenTag() } label: { Image(systemName: "eye.slash") }
            Button { showDrafts = true } label: { Image(systemName: "tray.full") }
            Spacer()
            Button { saveDraft(explicit: true) } label: {
                Text("存草稿").font(.system(size: 14))
            }
        }
        .font(.system(size: 20))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(XDTheme.card.ignoresSafeArea(edges: .bottom))
        .overlay(Divider(), alignment: .top)
    }

    private func prefill() {
        guard content.isEmpty && title.isEmpty && draftId == nil else { return }
        switch target {
        case .newThread(let fid):
            forumId = fid
            title = settings.defaultTitle
            name = settings.defaultName
        case .reply(_, let quote):
            if let quote { content = quote }
            name = settings.defaultName
        case .draft(let draft):
            title = draft.title
            name = draft.name
            content = draft.content
            draftId = draft.id
            forumId = (app.currentIsTimeline || app.currentForumId <= 0) ? nil : app.currentForumId
        case .report(let postId):
            forumId = ReportInfo.dutyRoomForumId
            content = ">>No.\(postId)\n"
        }
    }

    private func insertHiddenTag() {
        content += "[h][/h]"
    }

    private func saveDraft(explicit: Bool) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !title.isEmpty else {
            if explicit { Toast.shared.error("草稿是空的") }
            return
        }
        var draft = Draft(title: title, name: name, content: content)
        if let draftId { draft.id = draftId }
        DraftStore.shared.save(draft)
        draftId = draft.id
        if explicit { Toast.shared.success("已存入草稿箱") }
    }

    private func closeWithAutosave() {
        if settings.saveDraftAuto { saveDraft(explicit: false) }
        dismiss()
    }

    private func send() async {
        guard let cookie = cookies.cookieValue else {
            Toast.shared.error("请先添加并选择饼干")
            return
        }
        let mainPostId = replyTarget
        guard mainPostId != nil || forumId != nil else {
            Toast.shared.error("请先在顶部选择要发到哪个版块")
            return
        }
        if isReport && reportReason.isEmpty {
            Toast.shared.error("请先选择举报理由")
            return
        }
        let body = isReport ? "举报理由：\(reportReason)\n\(content)" : content

        isSending = true
        defer { isSending = false }

        var payload: XDImagePayload?
        if let image {
            payload = imageIsPNG ? ImageTools.preparePNG(image) : ImageTools.prepare(image, quality: settings.imageQuality)
            guard payload != nil else {
                Toast.shared.error("图片处理失败")
                return
            }
        }

        let createdAt = Date()
        do {
            if let mainPostId {
                try await XDAPI.shared.replyThread(mainPostId: mainPostId,
                                                   content: body,
                                                   name: name.isEmpty ? nil : name,
                                                   title: title.isEmpty ? nil : title,
                                                   watermark: settings.watermark,
                                                   image: payload,
                                                   cookie: cookie)
            } else if let forumId {
                try await XDAPI.shared.postThread(forumId: forumId,
                                                  content: body,
                                                  name: name.isEmpty ? nil : name,
                                                  title: title.isEmpty ? nil : title,
                                                  watermark: settings.watermark,
                                                  image: payload,
                                                  cookie: cookie)
            }

            HistoryStore.shared.recordPost(PostRecord(id: -Int(createdAt.timeIntervalSince1970),
                                                      kind: mainPostId == nil ? .thread : .reply,
                                                      mainPostId: mainPostId,
                                                      forumId: forumId,
                                                      title: title,
                                                      content: body,
                                                      userHash: cookies.selected?.userHash ?? "",
                                                      hasImage: payload != nil,
                                                      createdAt: createdAt))

            if let last = try? await XDAPI.shared.lastPost(cookie: cookie), last.id > 0 {
                HistoryStore.shared.fillLastPostId(last.id, for: createdAt)
                cookies.recordDisplayId(last.userHash)
            }

            if let mainPostId {
                AppState.shared.noteReplyPosted(mainPostId: mainPostId)
            } else {
                AppState.shared.noteThreadPosted()
            }

            if let draftId, let d = DraftStore.shared.drafts.first(where: { $0.id == draftId }) {
                DraftStore.shared.remove(d)
            }
            Toast.shared.success("发送成功")
            dismiss()
        } catch {
            Toast.shared.error(error)
        }
    }
}

struct EmoticonPickerView: View {
    var onPick: (String) -> Void

    @ObservedObject private var store = EmoticonStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newText = ""

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                    if !store.recent.isEmpty {
                        section("最近使用", store.recent)
                    }
                    ForEach(store.sections, id: \.group) { section in
                        self.section(section.group.rawValue, section.items)
                    }
                }
                .padding(12)
            }
            .background(XDTheme.background)
            .navigationTitle("颜文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Toggle("最近", isOn: $store.sortByRecent)
                        .toggleStyle(.button)
                        .font(.system(size: 13))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("添加颜文字", isPresented: $showAdd) {
                TextField("显示名称", text: $newName)
                TextField("内容", text: $newText)
                Button("添加") {
                    store.addCustom(name: newName, text: newText)
                    newName = ""; newText = ""
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Emoticon]) -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { e in
                    Button {
                        onPick(e.text)
                        store.markUsed(e)
                        Haptics.selection()
                    } label: {
                        Text(e.name)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(XDTheme.card))
                            .foregroundStyle(XDTheme.text)
                    }
                    .contextMenu {
                        if e.group == .custom {
                            Button(role: .destructive) { store.removeCustom(e) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        } header: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(XDTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .background(XDTheme.background)
        }
    }
}

struct DraftPickerSheet: View {
    var onPick: (Draft) -> Void

    @ObservedObject private var drafts = DraftStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if drafts.drafts.isEmpty {
                    EmptyStateView(icon: "tray", title: "草稿箱是空的",
                                   subtitle: "点右下角「存草稿」就能把当前内容存进来。")
                } else {
                    List {
                        ForEach(drafts.drafts) { draft in
                            Button {
                                onPick(draft)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }
}
