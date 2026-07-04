import Foundation

enum ServerLog {
    static func info(_ message: String) {
        write(message, to: .standardOutput)
    }

    static func error(_ message: String) {
        write(message, to: .standardError)
    }

    private static func write(_ message: String, to handle: FileHandle) {
        guard let data = "\(message)\n".data(using: .utf8) else {
            return
        }

        handle.write(data)
    }
}
