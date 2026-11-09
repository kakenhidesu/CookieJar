import SwiftUI

struct EmoticonEditorScreen: View {
    let original: Emoticon?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @State private var name: String
    @State private var text: String
    @State private var selection: NSRange
    @State private var focused = false
    @StateObject private var editorHandle = ComposeEditorHandle()

    init(original: Emoticon?) {
        self.original = original
        _name = State(initialValue: original?.name ?? "")
        _text = State(initialValue: original?.text ?? "")
        _selection = State(initialValue: NSRange(location: ((original?.text ?? "") as NSString).length, length: 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") { TextField("显示名称", text: $name) }
                Section("内容") {
                    ComposeTextEditor(text: $text, selection: $selection, focused: $focused,
                                      fontSize: 15, tint: settings.accent.color, textArt: true, handle: editorHandle)
                        .frame(minHeight: 220)
                }
                Section("预览") { EmoticonArtPreview(text: text) }
            }
            .navigationTitle(original == nil ? "添加颜文字" : "编辑颜文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let committed = editorHandle.finishComposition() { text = committed.text }
                        if EmoticonStore.shared.saveCustom(original: original, name: name, text: text) {
                            dismiss()
                        }
                    }
                    .disabled(text.isEmpty)
                }
            }
            .overlay { ToastOverlay() }
        }
    }
}

struct EmoticonPreviewScreen: View {
    let item: Emoticon
    var onInsert: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView { EmoticonArtPreview(text: item.text).padding() }
                .navigationTitle(item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("插入", action: onInsert) }
                }
        }
    }
}

private struct EmoticonArtPreview: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(verbatim: text)
                .font(.system(size: 15, design: .monospaced))
                .fixedSize(horizontal: true, vertical: true)
                .textSelection(.enabled)
                .padding(.vertical, 8)
        }
    }
}
