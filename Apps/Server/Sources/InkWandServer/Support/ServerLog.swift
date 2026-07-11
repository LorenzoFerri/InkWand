import Foundation

enum ServerLog {
    private static let lock = NSLock()
    private static let logURL: URL? = {
        #if os(macOS)
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("InkWand", isDirectory: true)
        else { return nil }
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".local/share/inkwand", isDirectory: true)
        #endif
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("server.log")
    }()

    static func info(_ message: String) {
        write(message, to: .standardOutput)
    }

    static func error(_ message: String) {
        write(message, to: .standardError)
    }

    private static func write(_ message: String, to handle: FileHandle) {
        let timestamped = "\(Self.timestamp()) \(message)"
        guard let data = "\(timestamped)\n".data(using: .utf8) else {
            return
        }

        handle.write(data)
        appendToLogFile(data)
    }

    private static func appendToLogFile(_ data: Data) {
        guard let logURL else { return }
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let file = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: data)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
