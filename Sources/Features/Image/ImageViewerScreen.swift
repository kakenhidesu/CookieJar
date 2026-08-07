import SwiftUI
import Photos

struct ImageViewerScreen: View {
    let payload: ImageViewerPayload
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var showControls = true

    init(payload: ImageViewerPayload) {
        self.payload = payload
        _index = State(initialValue: payload.index)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(payload.images.enumerated()), id: \.offset) { i, url in
                    ZoomableImage(url: url) {
                        withAnimation { showControls.toggle() }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if showControls {
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
    }

    private func save() async {
        guard let url = payload.images[safe: index] else { return }
        guard let data = await ImageCache.shared.rawData(for: url), let img = UIImage(data: data) else {
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
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        Toast.shared.success("已保存到相册")
    }
}

struct ZoomableImage: View {
    let url: URL
    var onSingleTap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            XDAsyncImage(url: url, contentMode: .fit) {
                AnyView(Color.black)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale)
            .offset(offset)
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
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
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
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
