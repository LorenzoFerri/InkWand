import Foundation

public struct AutostartEntry: Equatable, Sendable {
    public var name: String
    public var appImagePath: String

    public init(name: String = "InkWand", appImagePath: String) {
        self.name = name
        self.appImagePath = appImagePath
    }

    public var desktopFile: String {
        """
        [Desktop Entry]
        Type=Application
        Name=\(name)
        Exec=\(Self.escapeDesktopExec(appImagePath))
        X-GNOME-Autostart-enabled=true
        Terminal=false
        Categories=Utility;
        """
    }

    private static func escapeDesktopExec(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum AutostartState: Equatable, Sendable {
    case disabled
    case enabled(path: String)
    case stale(path: String, expectedPath: String)
}

public final class AutostartManager: @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        homeDirectory
            .appendingPathComponent(".config")
            .appendingPathComponent("autostart")
            .appendingPathComponent("inkwand.desktop")
    }

    public func state(expectedAppImagePath: String) -> AutostartState {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return .disabled
        }
        guard let execLine = contents.split(separator: "\n").first(where: { $0.hasPrefix("Exec=") }) else {
            return .disabled
        }
        let path = String(execLine.dropFirst("Exec=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return path == expectedAppImagePath ? .enabled(path: path) : .stale(path: path, expectedPath: expectedAppImagePath)
    }

    public func enable(appImagePath: String, name: String = "InkWand") throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entry = AutostartEntry(name: name, appImagePath: appImagePath)
        try entry.desktopFile.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func disable() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
