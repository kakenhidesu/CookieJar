import SwiftUI
import UniformTypeIdentifiers

private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalidFile }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupScreen: View {
    @State private var document: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var selected: BackupArchive?
    @State private var selectedName = ""
    @State private var merge = true
    @State private var isBusy = false
    @State private var status = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button { Task { await exportBackup() } } label: {
                    Label("导出备份", systemImage: "square.and.arrow.up")
                }
            }

            Section("导入") {
                Button { showImporter = true } label: {
                    Label("选择备份文件", systemImage: "folder")
                }
                if let selected {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedName).lineLimit(2)
                        Text(selected.createdAt, style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("浏览记录", value: "\(selected.history.browsing.count) 串")
                    LabeledContent("正文记录", value: "\(selected.search.count) 条")
                    LabeledContent("草稿", value: "\(selected.drafts.drafts.count) 条")
                    Picker("导入方式", selection: $merge) {
                        Text("合并").tag(true)
                        Text("覆盖").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(merge ? "合并记录，重复项保留较新内容，并应用备份设置。" : "用备份替换本机记录和设置。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("导入备份") { Task { await importBackup() } }
                }
            }
            if isBusy { ProgressView(status) }
        }
        .disabled(isBusy)
        .navigationTitle("备份与迁移")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isBusy)
        .fileExporter(isPresented: $showExporter, document: document, contentType: .json,
                      defaultFilename: backupFilename) { result in
            document = nil
            switch result {
            case .success: Toast.shared.success("备份已导出")
            case .failure(let error): showError(error)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await loadBackup(url) }
            case .failure(let error): showError(error)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { errorMessage != nil },
                                             set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor
    private func exportBackup() async {
        guard !isBusy else { return }
        isBusy = true
        status = "正在生成备份…"
        defer { isBusy = false }
        do {
            let archive = try await BackupService.capture()
            let data = try await Task.detached(priority: .userInitiated) {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                return try encoder.encode(archive)
            }.value
            document = BackupDocument(data: data)
            showExporter = true
        } catch { errorMessage = "生成备份失败，请重试。" }
    }

    @MainActor
    private func loadBackup(_ url: URL) async {
        isBusy = true
        status = "正在读取备份…"
        defer { isBusy = false }
        do {
            let archive = try await Task.detached(priority: .userInitiated) {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let archive = try decoder.decode(BackupArchive.self, from: data)
                try archive.validate()
                return archive
            }.value
            selected = archive
            selectedName = url.lastPathComponent
        } catch {
            errorMessage = (error as? BackupError)?.localizedDescription ?? "无法读取这个备份文件。"
        }
    }

    @MainActor
    private func importBackup() async {
        guard !isBusy, let selected else { return }
        isBusy = true
        status = "正在导入…"
        defer { isBusy = false }
        do {
            try await BackupService.restore(selected, merge: merge)
            self.selected = nil
            selectedName = ""
            Toast.shared.success("备份已导入")
        } catch { errorMessage = error.localizedDescription }
    }

    private func showError(_ error: Error) {
        if (error as NSError).code != NSUserCancelledError { errorMessage = "文件操作失败，请重试。" }
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "CookieJar-" + formatter.string(from: Date())
    }
}
