import SwiftUI
import UIKit

actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

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

    func image(for url: URL) async -> UIImage? {
        if let img = memory.object(forKey: url.absoluteString as NSString) { return img }
        if let task = inflight[url] { return await task.value }

        let task = Task<UIImage?, Never> {
            let file = fileURL(for: url)
            if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
                store(img, data: data, url: url, writeDisk: false)
                return img
            }
            do {
                var req = URLRequest(url: url)
                req.setValue(XDHTTP.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else { return nil }
                store(img, data: data, url: url, writeDisk: true)
                return img
            } catch {
                return nil
            }
        }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        return result
    }

    private func store(_ image: UIImage, data: Data, url: URL, writeDisk: Bool) {
        memory.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)
        if writeDisk {
            try? data.write(to: fileURL(for: url), options: .atomic)
        }
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
    var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
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
            let img = await ImageCache.shared.image(for: url)
            if img == nil { failed = true }
            withAnimation(.easeOut(duration: 0.18)) { image = img }
        }
    }
}

extension XDAsyncImage where Placeholder == AnyView {
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode, placeholder: {
            AnyView(Rectangle().fill(XDTheme.hairline.opacity(0.4)))
        })
    }
}
