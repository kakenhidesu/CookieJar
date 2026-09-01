import SwiftUI
import Photos

@MainActor
enum ImageOrigin {
    static var url: URL?
    static var frame: CGRect = .zero
}

struct ImageViewerScreen: View {
    let payload: ImageViewerPayload
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var showControls = true
    @State private var dimOpacity: Double = 1
    @State private var isDraggingDown = false

    init(payload: ImageViewerPayload) {
        self.payload = payload
        _index = State(initialValue: payload.index)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(dimOpacity).ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(payload.images.enumerated()), id: \.offset) { i, url in
                    ZoomableImage(url: url,
                                  onSingleTap: { withAnimation { showControls.toggle() } },
                                  onDismiss: { closeNow() },
                                  onDismissProgress: { p in
                                      dimOpacity = 1 - Double(p)
                                      isDraggingDown = p > 0
                                  })
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if showControls && !isDraggingDown {
                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .padding(10)
                                .background(Circle().fill(.black.opacity(0.45)))
                        }
                        Spacer()
                        Text("\(index + 1) / \(payload.images.count)")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.45)))
                        Spacer()
                        Menu {
                            Button {
                                Task { await save() }
                            } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
                            Button {
                                copyToPasteboard(payload.images[safe: index]?.absoluteString,
                                                 message: "已复制图片链接")
                            } label: { Label("复制链接", systemImage: "link") }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .padding(10)
                                .background(Circle().fill(.black.opacity(0.45)))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                }
                .transition(.opacity)
            }

            ToastOverlay()
        }
        .statusBarHidden(!showControls)
        .presentationBackground(.clear)
    }

    private func closeNow() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dismiss() }
    }

    private func save() async {
        guard let url = payload.images[safe: index] else { return }
        guard let data = await ImageCache.shared.rawData(for: url) else {
            Toast.shared.error("图片还没加载完")
            return
        }
        let status = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { c.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else {
            Toast.shared.error("没有相册权限")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            Toast.shared.success("已保存到相册")
        } catch {
            Toast.shared.error("保存失败")
        }
    }
}

struct ZoomableImage: View {
    let url: URL
    var onSingleTap: () -> Void
    var onDismiss: () -> Void = {}
    var onDismissProgress: (CGFloat) -> Void = { _ in }

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dismissOffset: CGSize = .zero
    @State private var dismissScale: CGFloat?
    @State private var dragIsVertical: Bool?
    @State private var isClosing = false
    @State private var imageSize: CGSize?

    private var dismissProgress: CGFloat {
        min(max(dismissOffset.height, 0) / 350, 1)
    }

    var body: some View {
        GeometryReader { geo in
            content
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(dismissScale ?? (scale * (1 - 0.25 * dismissProgress)))
            .offset(x: offset.width + dismissOffset.width,
                    y: offset.height + dismissOffset.height)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value, 1), 6)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 {
                            withAnimation(.spring()) {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard !isClosing else { return }
                        if scale > 1 {
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                            return
                        }
                        if dragIsVertical == nil {
                            let t = value.translation
                            guard abs(t.width) + abs(t.height) > 10 else { return }
                            dragIsVertical = abs(t.height) > abs(t.width)
                        }
                        guard dragIsVertical == true else { return }
                        dismissOffset = value.translation
                        onDismissProgress(dismissProgress)
                    }
                    .onEnded { value in
                        guard !isClosing else { return }
                        if scale > 1 {
                            lastOffset = offset
                            dragIsVertical = nil
                            return
                        }
                        let wasVertical = dragIsVertical == true
                        dragIsVertical = nil
                        guard wasVertical else { return }
                        if dismissOffset.height > 120 || value.predictedEndTranslation.height > 300 {
                            isClosing = true
                            let selfFrame = geo.frame(in: .global)
                            if ImageOrigin.url == url, ImageOrigin.frame.width > 1 {
                                let target = ImageOrigin.frame
                                var shrink = target.width / max(selfFrame.width, 1)
                                if let size = imageSize, size.width > 0, size.height > 0 {
                                    let fit = min(geo.size.width / size.width, geo.size.height / size.height)
                                    let dispW = size.width * fit
                                    let dispH = size.height * fit
                                    shrink = min(target.width / max(dispW, 1), target.height / max(dispH, 1))
                                }
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    dismissScale = max(shrink, 0.02)
                                    dismissOffset = CGSize(width: target.midX - selfFrame.midX,
                                                           height: target.midY - selfFrame.midY)
                                    onDismissProgress(1)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { onDismiss() }
                            } else {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    dismissOffset.height = geo.size.height
                                    onDismissProgress(1)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onDismiss() }
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                dismissOffset = .zero
                                onDismissProgress(0)
                            }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1 {
                        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2.5; lastScale = 2.5
                    }
                }
            }
            .onTapGesture { onSingleTap() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if GIF.isGIF(url: url) {
            XDGIFImage(primary: url,
                       contentMode: .fit,
                       maxPixel: 1024,
                       budgetBytes: 32 * 1024 * 1024,
                       placeholder: Color.black,
                       onLoaded: { imageSize = $0.size })
        } else {
            XDAsyncImage(url: url, contentMode: .fit,
                         onLoaded: { imageSize = $0.size }) {
                AnyView(Color.black)
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
