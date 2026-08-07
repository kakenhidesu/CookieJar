import SwiftUI

enum FeedSort: String, CaseIterable, Identifiable {
    case `default`, newest, oldest, replies, title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: return "默认顺序"
        case .newest: return "最新发串"
        case .oldest: return "最早发串"
        case .replies: return "回应最多"
        case .title: return "按标题"
        }
    }

    var icon: String {
        switch self {
        case .default: return "list.bullet"
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .replies: return "bubble.left"
        case .title: return "textformat"
        }
    }

    func apply(to items: [XDPost]) -> [XDPost] {
        switch self {
        case .default: return items
        case .newest: return items.sorted { $0.postTime > $1.postTime }
        case .oldest: return items.sorted { $0.postTime < $1.postTime }
        case .replies: return items.sorted { ($0.replyCount ?? 0) > ($1.replyCount ?? 0) }
        case .title: return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("set.accent") var accentRaw: String = XDTheme.Accent.purple.rawValue
    @AppStorage("set.appearance") var appearanceRaw: String = "system"
    @AppStorage("set.fontScale") var fontScale: Double = 1.0
    @AppStorage("set.lineSpacing") var lineSpacing: Double = 4
    @AppStorage("set.compactCard") var compactCard: Bool = false
    @AppStorage("set.showImages") var showImages: Bool = true

    @AppStorage("set.recordBrowsing") var recordBrowsing: Bool = true
    @AppStorage("set.restoreReadProgress") var restoreReadProgress: Bool = true
    @AppStorage("set.restoreLastThread") var restoreLastThread: Bool = true
    @AppStorage("set.showRelativeTime") var showRelativeTime: Bool = true
    @AppStorage("set.autoRevealHidden") var autoRevealHidden: Bool = false

    @AppStorage("set.watermark") var watermark: Bool = false
    @AppStorage("set.defaultName") var defaultName: String = ""
    @AppStorage("set.defaultTitle") var defaultTitle: String = ""
    @AppStorage("set.imageQuality") var imageQuality: Double = 0.8
    @AppStorage("set.saveDraftAuto") var saveDraftAuto: Bool = true

    @AppStorage("set.feedUUID") var feedUUID: String = ""
    @AppStorage("set.useHTMLFeed") var useHTMLFeed: Bool = false
    @AppStorage("set.feedSort") var feedSortRaw: String = FeedSort.default.rawValue

    var feedSort: FeedSort {
        get { FeedSort(rawValue: feedSortRaw) ?? .default }
        set { feedSortRaw = newValue.rawValue }
    }

    @AppStorage("set.useBackupAPI") var useBackupAPI: Bool = false
    @AppStorage("set.timeout") var timeout: Int = 20
    @AppStorage("set.updateEndpointsOnLaunch") var updateEndpointsOnLaunch: Bool = true

    @AppStorage("set.defaultForumId") var defaultForumId: Int = 1
    @AppStorage("set.defaultIsTimeline") var defaultIsTimeline: Bool = true

    var accent: XDTheme.Accent {
        get { XDTheme.Accent(rawValue: accentRaw) ?? .purple }
        set { accentRaw = newValue.rawValue }
    }

    var colorScheme: ColorScheme? {
        switch appearanceRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var contentFont: Font { .system(size: 16 * fontScale) }
    var titleFont: Font { .system(size: 16 * fontScale, weight: .semibold) }
    var metaFont: Font { .system(size: 12.5 * fontScale) }

    private init() {
        if feedUUID.isEmpty { feedUUID = UUID().uuidString }
    }

    func applyToNetwork() {
        XDAPI.shared.setUseBackupAPI(useBackupAPI)
        let t = timeout
        Task { await XDHTTP.shared.setTimeout(t) }
    }
}
