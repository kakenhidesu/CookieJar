import Foundation

enum BackupSetting: Codable {
    case string(String), bool(Bool), integer(Int), number(Double)

    var value: Any {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value
        case .integer(let value): return value
        case .number(let value): return value
        }
    }

    func hasSameType(as other: BackupSetting) -> Bool {
        switch (self, other) {
        case (.string, .string), (.bool, .bool), (.integer, .integer), (.number, .number): return true
        default: return false
        }
    }
}

enum BackupSettings {
    // Only user preferences are transferable; credentials and endpoint caches stay out.
    static let defaults: [String: BackupSetting] = [
        "set.accent": .string("基佬紫"), "set.appearance": .string("system"),
        "set.fontScale": .number(1), "set.lineSpacing": .number(4),
        "set.compactCard": .bool(false), "set.showImages": .bool(true),
        "set.recordBrowsing": .bool(true), "set.restoreReadProgress": .bool(true),
        "set.restoreLastThread": .bool(true), "set.showRelativeTime": .bool(true),
        "set.autoRevealHidden": .bool(false), "set.watermark": .bool(false),
        "set.defaultName": .string(""), "set.defaultTitle": .string(""),
        "set.imageQuality": .number(0.8), "set.saveDraftAuto": .bool(true),
        "set.feedUUID": .string(""), "set.useHTMLFeed": .bool(false),
        "set.feedSort": .string("default"), "set.feedOnlyUpdated": .bool(false),
        "set.feedUpdatedFirst": .bool(false), "set.useBackupAPI": .bool(false),
        "set.timeout": .integer(20), "set.updateEndpointsOnLaunch": .bool(true),
        "set.defaultForumId": .integer(1), "set.defaultIsTimeline": .bool(true),
        "forum.order": .string(""), "forum.hidden": .string(""),
        "emoticon.sortByRecent": .bool(true)
    ]

    static func capture() -> [String: BackupSetting] {
        let store = UserDefaults.standard
        var values = defaults
        for (key, fallback) in defaults where store.object(forKey: key) != nil {
            switch fallback {
            case .string: values[key] = .string(store.string(forKey: key) ?? "")
            case .bool: values[key] = .bool(store.bool(forKey: key))
            case .integer: values[key] = .integer(store.integer(forKey: key))
            case .number: values[key] = .number(store.double(forKey: key))
            }
        }
        values["set.accent"] = .string(SettingsStore.shared.accentRaw)
        values["set.feedUUID"] = .string(SettingsStore.shared.feedUUID)
        return values
    }

    static func validate(_ values: [String: BackupSetting]) throws {
        guard Set(values.keys) == Set(defaults.keys) else { throw BackupError.invalidFile }
        for (key, value) in values {
            guard let fallback = defaults[key], value.hasSameType(as: fallback) else {
                throw BackupError.invalidFile
            }
        }
        guard case .string(let uuid) = values["set.feedUUID"], !uuid.isEmpty else { throw BackupError.invalidFile }
        let ranges: [String: ClosedRange<Double>] = [
            "set.fontScale": 0.8...1.6, "set.lineSpacing": 0...12, "set.imageQuality": 0.3...1
        ]
        for (key, range) in ranges {
            if case .number(let value) = values[key], !range.contains(value) { throw BackupError.invalidFile }
        }
        if case .integer(let timeout) = values["set.timeout"], !(5...60).contains(timeout) {
            throw BackupError.invalidFile
        }
    }

    static func apply(_ values: [String: BackupSetting]) {
        SettingsStore.shared.objectWillChange.send()
        ForumStore.shared.objectWillChange.send()
        for (key, fallback) in defaults { UserDefaults.standard.set((values[key] ?? fallback).value, forKey: key) }
        SettingsStore.shared.applyToNetwork()
    }
}
