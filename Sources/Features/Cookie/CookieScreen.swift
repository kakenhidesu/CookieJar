import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins

struct CookieScreen: View {
    @EnvironmentObject private var cookies: CookieStore
    @State private var showScanner = false
    @State private var showManual = false
    @State private var showLogin = false
    @State private var manualText = ""
    @State private var exporting: XDCookie?

    var body: some View {
        List {
            Section {
                if cookies.cookies.isEmpty {
                    Text("还没有饼干。没有饼干只能浏览，不能发串。")
                        .font(.system(size: 13))
                        .foregroundStyle(XDTheme.secondaryText)
                }
                ForEach(cookies.cookies) { cookie in
                    Button {
                        cookies.select(cookie)
                        Haptics.selection()
                    } label: {
                        HStack {
                            Text(cookie.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(XDTheme.text)
                            Spacer()
                            if cookies.selected?.userHash == cookie.userHash {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            cookies.remove(cookie)
                        } label: { Label("删除", systemImage: "trash") }
                        Button {
                            exporting = cookie
                        } label: { Label("导出", systemImage: "qrcode") }
                        .tint(.blue)
                    }
                }
                .onMove { cookies.move(from: $0, to: $1) }
            } header: {
                Text("我的饼干")
            } footer: {
                Text("左滑可以导出成二维码或删除；点击切换当前使用的饼干。")
            }

            Section("添加饼干") {
                Button {
                    showScanner = true
                } label: { Label("扫描二维码", systemImage: "qrcode.viewfinder") }

                Button {
                    if let text = UIPasteboard.general.string, let c = CookieStore.parse(text) {
                        importCookie(c)
                    } else {
                        Toast.shared.error("剪贴板里没有有效的饼干")
                    }
                } label: { Label("从剪贴板导入", systemImage: "doc.on.clipboard") }

                Button {
                    showManual = true
                } label: { Label("手动输入 userhash", systemImage: "keyboard") }
            }

            Section {
                Button {
                    showLogin = true
                } label: { Label("X 岛账号饼干管理", systemImage: "person.badge.key") }
            } header: {
                Text("账号饼干")
            } footer: {
                Text("登录 X 岛官方账号，可领取新饼干、导入到本地或永久注销。")
            }

            Section {
                Text("饼干保存在系统钥匙串（Keychain）中，不会上传到任何第三方。")
                    .font(.system(size: 12))
                    .foregroundStyle(XDTheme.secondaryText)
            }
        }
        .navigationTitle("饼干管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { text in
                showScanner = false
                if let c = CookieStore.parse(text) {
                    importCookie(c)
                } else {
                    Toast.shared.error("二维码里没有饼干信息")
                }
            }
        }
        .sheet(item: $exporting) { cookie in
            CookieExportSheet(cookie: cookie)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet()
        }
        .alert("手动添加饼干", isPresented: $showManual) {
            TextField("userhash", text: $manualText)
            Button("添加") {
                if let c = CookieStore.parse(manualText) {
                    importCookie(c)
                    manualText = ""
                } else {
                    Toast.shared.error("无效的 userhash")
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func importCookie(_ c: XDCookie) {
        let added = cookies.add(c)
        Toast.shared.success(added ? "已添加饼干 \(c.name)" : "饼干已存在，已更新")
    }
}

struct CookieExportSheet: View {
    let cookie: XDCookie
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?

    private static func makeQR(_ text: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(cookie.name).font(.system(size: 16, weight: .medium))
                Text(cookie.userHash)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(XDTheme.secondaryText)
                    .textSelection(.enabled)
                Button {
                    copyToPasteboard(CookieStore.shared.exportText(cookie), message: "已复制饼干")
                } label: { Label("复制饼干", systemImage: "doc.on.doc") }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
            .task { qrImage = CookieExportSheet.makeQR(CookieStore.shared.exportText(cookie)) }
            .navigationTitle("导出饼干")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

struct QRScannerSheet: View {
    var onResult: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView(onResult: onResult)
                    .ignoresSafeArea()
                VStack {
                    Spacer()
                    Text("把 X 岛饼干二维码放进取景框")
                        .font(.system(size: 14))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .foregroundStyle(.white)
                        .padding(.bottom, 60)
                }
            }
            .navigationTitle("扫描饼干")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onResult: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.onResult = onResult
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onResult: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var handled = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer

            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !handled,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue else { return }
            handled = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            session.stopRunning()
            onResult?(value)
        }
    }
}

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cookies: CookieStore

    @State private var email = ""
    @State private var password = ""
    @State private var verify = ""
    @State private var verifyImage: UIImage?
    @State private var isWorking = false
    @State private var loggedIn = false
    @State private var info: CookiesListInfo?
    @State private var remoteNames: [Int: String] = [:]
    @State private var pendingAction: CookieAction?

    private enum CookieAction: Identifiable {
        case apply
        case delete(id: Int, name: String)

        var id: String {
            switch self {
            case .apply: return "apply"
            case .delete(let id, _): return "delete-\(id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !loggedIn {
                    Section("账号") {
                        TextField("邮箱", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        SecureField("密码", text: $password)
                        HStack {
                            TextField("验证码", text: $verify)
                                .textInputAutocapitalization(.never)
                            Spacer()
                            Button {
                                Task { await loadVerify() }
                            } label: {
                                if let verifyImage {
                                    Image(uiImage: verifyImage)
                                        .resizable().scaledToFit().frame(height: 34)
                                } else {
                                    Text("点击获取").font(.system(size: 13))
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            Task { await login() }
                        } label: {
                            HStack {
                                if isWorking { ProgressView() }
                                Text("登录")
                            }
                        }
                        .disabled(isWorking || email.isEmpty || password.isEmpty || verify.isEmpty)
                    } footer: {
                        Text("登录只用于从官方账号导出饼干，账号密码不会被保存。")
                    }
                } else {
                    Section {
                        if let info {
                            LabeledContent("饼干槽", value: "\(info.current) / \(info.total)")
                            LabeledContent("领取通道", value: info.canGetCookie ? "已开放" : "已关闭")
                            ForEach(info.ids, id: \.self) { id in
                                HStack {
                                    Text(remoteNames[id] ?? "读取中…")
                                        .foregroundStyle(remoteNames[id] == nil ? XDTheme.secondaryText : XDTheme.text)
                                    Spacer()
                                    if cookies.cookies.contains(where: { $0.remoteId == id }) {
                                        Text("已导入")
                                            .font(.system(size: 13))
                                            .foregroundStyle(XDTheme.secondaryText)
                                    } else {
                                        Button("导入") {
                                            Task { await importCookie(id) }
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        pendingAction = .delete(id: id,
                                                                name: remoteNames[id] ?? String(format: "饼干 #%d", id))
                                    } label: { Label("注销", systemImage: "trash") }
                                }
                            }
                            if info.canGetCookie {
                                Button {
                                    pendingAction = .apply
                                } label: { Label("领取新饼干", systemImage: "plus.circle") }
                                .disabled(info.current >= info.total)
                            }
                        } else {
                            ProgressView()
                        }
                    } header: {
                        Text("账号饼干")
                    }
                    Section {
                        Button("退出登录", role: .destructive) {
                            Task {
                                await XDAPI.shared.logout()
                                loggedIn = false
                                info = nil
                            }
                        }
                    }
                }
            }
            .navigationTitle(loggedIn ? "账号饼干" : "登录 X 岛")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .task {
                loggedIn = await XDHTTP.shared.isLoggedIn
                if loggedIn { await loadCookiesList() } else { await loadVerify() }
            }
            .overlay { ToastOverlay() }
            .sheet(item: $pendingAction) { action in
                switch action {
                case .apply:
                    CookieVerifySheet(title: "领取新饼干",
                                      message: "饼干烘焙中...",
                                      confirmTitle: "领取",
                                      isDestructive: false,
                                      perform: { try await XDAPI.shared.applyCookie(verify: $0) },
                                      onSuccess: { Task { await actionSucceeded(action) } })
                case .delete(let id, let name):
                    CookieVerifySheet(title: "注销饼干",
                                      message: "你确定要碎掉这块饼干吗？“\(name)”将会永久消失！（真的很久！）",
                                      confirmTitle: "永久注销",
                                      isDestructive: true,
                                      perform: { try await XDAPI.shared.deleteCookie(id: id, verify: $0) },
                                      onSuccess: { Task { await actionSucceeded(action) } })
                }
            }
        }
    }

    private func actionSucceeded(_ action: CookieAction) async {
        switch action {
        case .apply:
            Toast.shared.success("已领取新饼干")
        case .delete(let id, _):
            remoteNames.removeValue(forKey: id)
            if let local = cookies.cookies.first(where: { $0.remoteId == id }) {
                cookies.remove(local)
            }
            Toast.shared.success("饼干已注销")
        }
        await loadCookiesList()
    }

    private func loadVerify() async {
        do {
            let data = try await XDAPI.shared.verifyImage()
            verifyImage = UIImage(data: data)
        } catch {
            Toast.shared.error(error)
        }
    }

    private func login() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await XDAPI.shared.login(email: email, password: password, verify: verify)
            loggedIn = true
            password = ""
            await loadCookiesList()
            Toast.shared.success("登录成功")
        } catch {
            Toast.shared.error(error)
            await loadVerify()
        }
    }

    private func loadCookiesList() async {
        do {
            let list = try await XDAPI.shared.cookiesList()
            info = list
            for id in list.ids where remoteNames[id] == nil {
                if let cookie = try? await XDAPI.shared.exportCookie(id: id) {
                    remoteNames[id] = cookie.name
                } else {
                    remoteNames[id] = String(format: "饼干 #%d", id)
                }
            }
        } catch {
            Toast.shared.error(error)
        }
    }

    private func importCookie(_ id: Int) async {
        do {
            let cookie = try await XDAPI.shared.exportCookie(id: id)
            _ = cookies.add(cookie)
            remoteNames[id] = cookie.name
            Toast.shared.success("已导入 \(cookie.name)")
        } catch {
            Toast.shared.error(error)
        }
    }
}

struct CookieVerifySheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let isDestructive: Bool
    let perform: (String) async throws -> Void
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var verify = ""
    @State private var verifyImage: UIImage?
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(isDestructive ? XDTheme.admin : XDTheme.text)
                }
                Section {
                    HStack {
                        TextField("输入验证码", text: $verify)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Spacer()
                        Button {
                            Task { await loadVerify() }
                        } label: {
                            if let verifyImage {
                                Image(uiImage: verifyImage)
                                    .resizable().scaledToFit().frame(height: 34)
                            } else {
                                Text("点击获取").font(.system(size: 13))
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("验证码")
                } footer: {
                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(XDTheme.admin)
                    }
                }
                Section {
                    Button(role: isDestructive ? .destructive : nil) {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isWorking { ProgressView() }
                            Text(confirmTitle)
                        }
                    }
                    .disabled(isWorking || verify.isEmpty)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .task { await loadVerify() }
        }
        .presentationDetents([.medium])
    }

    private func loadVerify() async {
        verifyImage = nil
        do {
            let data = try await XDAPI.shared.verifyImage()
            verifyImage = UIImage(data: data)
        } catch {
            Toast.shared.error(error)
        }
    }

    private func submit() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await perform(verify)
            onSuccess()
            dismiss()
        } catch {
            errorText = error.localizedDescription
            verify = ""
            await loadVerify()
        }
    }
}
