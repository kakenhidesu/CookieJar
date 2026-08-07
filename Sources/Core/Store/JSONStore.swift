import Foundation

enum AppPaths {
    static var dataDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CookieJar", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func file(_ name: String) -> URL {
        dataDirectory.appendingPathComponent(name)
    }
}

final class JSONStore<T: Codable> {
    private let url: URL
    private let queue = DispatchQueue(label: "xd.jsonstore", qos: .utility)
    private var pending: DispatchWorkItem?

    init(filename: String) {
        url = AppPaths.file(filename)
    }

    func load() -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    func save(_ value: T) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.write(value) }
        pending = item
        queue.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func saveNow(_ value: T) {
        pending?.cancel()
        write(value)
    }

    private func write(_ value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
