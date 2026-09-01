import SwiftUI
import UIKit
import ImageIO

actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    init() {
        memory.countLimit = 60
        memory.totalCostLimit = 32 * 1024 * 1024
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("XDImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fileURL(for url: URL) -> URL {
        let key = url.absoluteString
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return dir.appendingPathComponent(String(key.suffix(120)))
    }

    func image(for url: URL, maxPixel: CGFloat = 0) async -> UIImage? {
        let key = "\(Int(maxPixel))|\(url.absoluteString)"
        if let img = memory.object(forKey: key as NSString) { return img }
        if let task = inflight[key] { return await task.value }

        let file = fileURL(for: url)
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let data = try? Data(contentsOf: file) {
                return ImageCache.decode(data, maxPixel: maxPixel)
            }
            guard let data = try? await ImageCache.fetch(url) else { return nil }
            try? data.write(to: file, options: .atomic)
            return ImageCache.decode(data, maxPixel: maxPixel)
        }
        inflight[key] = task
        let result = await task.value
        if let result {
            memory.setObject(result, forKey: key as NSString, cost: ImageCache.decodedCost(result))
        }
        inflight[key] = nil
        return result
    }

    private static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, srcOpts) else {
            return UIImage(data: data)
        }
        var opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if maxPixel > 0 { opts[kCGImageSourceThumbnailMaxPixelSize] = maxPixel }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(XDHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private static func decodedCost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }

    func dropMemory() {
        memory.removeAllObjects()
    }

    func rawData(for url: URL) async -> Data? {
        let file = fileURL(for: url)
        if let data = try? Data(contentsOf: file) { return data }
        var req = URLRequest(url: url)
        req.setValue(XDHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? data.write(to: file, options: .atomic)
        return data
    }

    func diskSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, f in
            sum + Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clearDisk() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        memory.removeAllObjects()
    }
}

struct XDAsyncImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode
    var maxPixel: CGFloat
    var onLoaded: ((UIImage) -> Void)?
    var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, contentMode: ContentMode = .fill, maxPixel: CGFloat = 0,
         onLoaded: ((UIImage) -> Void)? = nil,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.maxPixel = maxPixel
        self.onLoaded = onLoaded
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                placeholder()
                    .overlay(
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(XDTheme.secondaryText)
                    )
            } else {
                placeholder()
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: url) {
            guard let url else { failed = true; return }
            image = nil
            failed = false
            let img = await ImageCache.shared.image(for: url, maxPixel: maxPixel)
            if img == nil { failed = true }
            withAnimation(.easeOut(duration: 0.18)) { image = img }
            if let img { onLoaded?(img) }
        }
    }
}

extension XDAsyncImage where Placeholder == AnyView {
    init(url: URL?, contentMode: ContentMode = .fill, maxPixel: CGFloat = 0) {
        self.init(url: url, contentMode: contentMode, maxPixel: maxPixel, placeholder: {
            AnyView(Rectangle().fill(XDTheme.hairline.opacity(0.4)))
        })
    }
}
