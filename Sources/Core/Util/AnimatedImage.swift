import SwiftUI
import UIKit
import ImageIO

enum GIF {
    static func isGIF(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".gif")
    }

    static func isGIF(url: URL) -> Bool {
        url.pathExtension.lowercased() == "gif"
    }

    static func animated(from data: Data, maxPixel: CGFloat, budgetBytes: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        var frames: [UIImage] = []
        var duration: Double = 0
        var bytes = 0

        for index in 0..<count {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            bytes += cg.width * cg.height * 4
            if bytes > budgetBytes && frames.count >= 2 { break }
            frames.append(UIImage(cgImage: cg))
            duration += delay(source, index)
        }

        guard frames.count > 1 else { return nil }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func delay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let seconds = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        return seconds < 0.011 ? 0.1 : seconds
    }
}

private struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode
        if view.image !== image {
            view.image = image
            view.startAnimating()
        }
    }
}

struct XDGIFImage: View {
    let primary: URL
    var fallback: URL?
    var contentMode: ContentMode = .fill
    var maxPixel: CGFloat = 240
    var budgetBytes: Int = 8 * 1024 * 1024
    var placeholder: Color = XDTheme.hairline.opacity(0.4)
    var onLoaded: ((UIImage) -> Void)?

    @State private var animated: UIImage?
    @State private var still: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let animated {
                AnimatedImageView(image: animated,
                                  contentMode: contentMode == .fill ? .scaleAspectFill : .scaleAspectFit)
            } else if let still {
                Image(uiImage: still)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                placeholder.overlay(
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(XDTheme.secondaryText)
                )
            } else {
                placeholder.overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: primary) { await load() }
    }

    private func load() async {
        animated = nil
        still = nil
        failed = false
        defer {
            if let img = animated ?? still { onLoaded?(img) }
        }

        if let data = await ImageCache.shared.rawData(for: primary) {
            if let frames = await decode(data) {
                animated = frames
                return
            }
            still = UIImage(data: data)
        }

        guard let fallback, let data = await ImageCache.shared.rawData(for: fallback) else {
            if still == nil { failed = true }
            return
        }
        if let frames = await decode(data) {
            animated = frames
        } else if let image = UIImage(data: data) {
            still = image
        } else if still == nil {
            failed = true
        }
    }

    private func decode(_ data: Data) async -> UIImage? {
        let pixel = maxPixel
        let budget = budgetBytes
        return await Task.detached(priority: .utility) {
            GIF.animated(from: data, maxPixel: pixel, budgetBytes: budget)
        }.value
    }
}
