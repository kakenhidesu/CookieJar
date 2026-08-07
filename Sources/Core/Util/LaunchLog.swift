import Foundation
import Darwin

private var crashLogFD: Int32 = -1

private func signalName(_ sig: Int32) -> StaticString {
    switch sig {
    case SIGABRT: return "SIGABRT"
    case SIGSEGV: return "SIGSEGV"
    case SIGBUS: return "SIGBUS"
    case SIGILL: return "SIGILL"
    case SIGFPE: return "SIGFPE"
    case SIGTRAP: return "SIGTRAP"
    default: return "SIGNAL"
    }
}

private func writeRaw(_ text: StaticString) {
    guard crashLogFD >= 0 else { return }
    _ = write(crashLogFD, text.utf8Start, text.utf8CodeUnitCount)
}

private func xdCrashSignalHandler(_ sig: Int32) {
    writeRaw("\n*** 崩溃 ")
    writeRaw(signalName(sig))
    writeRaw(" ***\n")

    if crashLogFD >= 0 {
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
        let count = backtrace(&frames, Int32(frames.count))
        backtrace_symbols_fd(&frames, count, crashLogFD)
    }

    signal(sig, SIG_DFL)
    raise(sig)
}

enum LaunchLog {
    private static let queue = DispatchQueue(label: "xd.launchlog")
    private static let maxBytes = 32 * 1024

    private static var currentURL: URL { AppPaths.file("launch.log") }
    private static var previousURL: URL { AppPaths.file("launch-previous.log") }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func startNewRun() {
        let fm = FileManager.default
        if fm.fileExists(atPath: currentURL.path) {
            try? fm.removeItem(at: previousURL)
            try? fm.moveItem(at: currentURL, to: previousURL)
        }
        let header = "=== \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium))"
            + " \(AppInfo.version) iOS \(ProcessInfo.processInfo.operatingSystemVersionString) ===\n"
        try? header.data(using: .utf8)?.write(to: currentURL, options: .atomic)

        installCrashHandlers()
    }

    private static func installCrashHandlers() {
        crashLogFD = open(currentURL.path, O_WRONLY | O_APPEND)

        NSSetUncaughtExceptionHandler { exception in
            let text = "\n*** 未捕获异常 \(exception.name.rawValue)：\(exception.reason ?? "无原因") ***\n"
                + exception.callStackSymbols.prefix(24).joined(separator: "\n") + "\n"
            LaunchLog.appendDirect(text)
        }

        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig, xdCrashSignalHandler)
        }
    }

    static func mark(_ text: String) {
        let line = "\(stamp.string(from: Date())) | \(text)\n"
        queue.async { appendDirect(line) }
    }

    fileprivate static func appendDirect(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: currentURL) {
            defer { try? handle.close() }
            if let end = try? handle.seekToEnd(), end < maxBytes {
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: currentURL, options: .atomic)
        }
    }

    static var footprintMB: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1024 / 1024)
    }

    static func report() -> String {
        let previous = (try? String(contentsOf: previousURL, encoding: .utf8)) ?? "（无）"
        let current = (try? String(contentsOf: currentURL, encoding: .utf8)) ?? "（无）"
        return """
        —— 上一次启动 ——
        \(previous)
        —— 本次启动 ——
        \(current)
        """
    }
}
