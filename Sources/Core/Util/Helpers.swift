import SwiftUI
import UIKit

enum AppInfo {
    private static func plist(_ key: String, _ fallback: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? fallback
    }

    static var version: String {
        "beta\(plist("CFBundleShortVersionString", "1.0"))_\(plist("CFBundleVersion", "25"))"
    }
}

enum RelativeTime {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func absolute(_ date: Date) -> String {
        guard date != .distantPast else { return "" }
        return formatter.string(from: date)
    }

    static func full(_ date: Date) -> String {
        guard date != .distantPast else { return "" }
        return fullFormatter.string(from: date)
    }

    static func display(_ date: Date, relative: Bool) -> String {
        guard date != .distantPast else { return "" }
        guard relative else { return shortFormatter.string(from: date) }
        let delta = Date().timeIntervalSince(date)
        switch delta {
        case ..<0: return shortFormatter.string(from: date)
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(delta / 60)) 分钟前"
        case ..<86400: return "\(Int(delta / 3600)) 小时前"
        default: return shortFormatter.string(from: date)
        }
    }

    private static let hourMinuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func hourMinute(_ date: Date) -> String {
        guard date != .distantPast else { return "" }
        if Date().timeIntervalSince(date) < 86400 {
            return hourMinuteFormatter.string(from: date)
        }
        return dateOnlyFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return dayFormatter.string(from: date)
    }
}

@discardableResult
func copyToPasteboard(_ text: String?, message: String = "已复制") -> Bool {
    guard let text, !text.isEmpty else { return false }
    UIPasteboard.general.string = text
    Toast.shared.show(message)
    return true
}

final class Toast: ObservableObject {
    static let shared = Toast()

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var icon: String?
        var isError: Bool
    }

    @Published var current: Message?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String, icon: String? = nil) {
        present(Message(text: text, icon: icon, isError: false))
    }

    func error(_ text: String) {
        present(Message(text: text, icon: "exclamationmark.triangle.fill", isError: true))
        Haptics.error()
    }

    func error(_ error: Error) {
        self.error(error.localizedDescription)
    }

    func success(_ text: String) {
        present(Message(text: text, icon: "checkmark.circle.fill", isError: false))
        Haptics.success()
    }

    private func present(_ message: Message) {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { current = message }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { current = nil }
        }
    }
}

struct ToastOverlay: View {
    @ObservedObject private var toast = Toast.shared

    var body: some View {
        VStack {
            Spacer()
            if let msg = toast.current {
                HStack(spacing: 8) {
                    if let icon = msg.icon {
                        Image(systemName: icon)
                    }
                    Text(msg.text)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(3)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(msg.isError ? Color.red.opacity(0.92) : Color.black.opacity(0.82))
                )
                .padding(.bottom, 84)
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: toast.current)
    }
}



enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

struct EmptyStateView: View {
    var icon: String = "tray"
    var title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(XDTheme.secondaryText.opacity(0.6))
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(XDTheme.secondaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(XDTheme.secondaryText.opacity(0.8))
                    .padding(.horizontal, 32)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct InlineLoading: View {
    var text: String = "加载中…"
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13)).foregroundStyle(XDTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct ListStatusView: View {
    var isLoading: Bool
    var error: String?
    var isEmpty: Bool
    var reachedEnd: Bool = false
    var emptyIcon: String = "tray"
    var emptyTitle: String = "这里空空如也"
    var emptySubtitle: String?
    var loadingText: String = "加载中…"
    var retry: (() -> Void)?
    var refresh: (() -> Void)?

    var body: some View {
        if isLoading {
            InlineLoading(text: loadingText)
        } else if let error, isEmpty {
            EmptyStateView(icon: "wifi.exclamationmark",
                           title: "加载失败",
                           subtitle: error,
                           actionTitle: retry != nil ? "重试" : nil,
                           action: retry)
        } else if error != nil {
            HStack(spacing: 8) {
                Text("加载失败")
                    .font(.system(size: 12))
                    .foregroundStyle(XDTheme.admin)
                if let retry {
                    Button {
                        retry()
                        Haptics.light()
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.system(size: 12))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 16)
        } else if isEmpty {
            EmptyStateView(icon: emptyIcon, title: emptyTitle, subtitle: emptySubtitle,
                           actionTitle: retry != nil ? "重新加载" : nil, action: retry)
        } else if reachedEnd {
            HStack(spacing: 8) {
                Text("已经到底了")
                    .font(.system(size: 12))
                    .foregroundStyle(XDTheme.secondaryText)
                if let refresh {
                    Button {
                        refresh()
                        Haptics.light()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.system(size: 12))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 16)
        }
    }
}

enum ImageTools {
    static func prepare(_ image: UIImage, quality: Double) -> XDImagePayload? {
        let limit = 2 * 1024 * 1024
        var q = max(0.3, min(1.0, quality))
        var data = image.jpegData(compressionQuality: q)
        var working = image

        while let d = data, d.count > limit {
            if q > 0.4 {
                q -= 0.15
            } else {
                let scale = 0.8
                let newSize = CGSize(width: working.size.width * scale, height: working.size.height * scale)
                working = resize(working, to: newSize)
            }
            data = working.jpegData(compressionQuality: q)
            if working.size.width < 400 { break }
        }
        guard let final = data else { return nil }
        let name = "img_\(Int(Date().timeIntervalSince1970)).jpg"
        return XDImagePayload(data: final, filename: name, mime: "image/jpeg")
    }

    static func resize(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    static func preparePNG(_ image: UIImage) -> XDImagePayload? {
        guard let data = image.pngData() else { return nil }
        if data.count > 2 * 1024 * 1024 {
            return prepare(image, quality: 0.8)
        }
        return XDImagePayload(data: data, filename: "doodle_\(Int(Date().timeIntervalSince1970)).png", mime: "image/png")
    }
}
