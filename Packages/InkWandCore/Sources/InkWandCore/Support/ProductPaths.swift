import Foundation

public struct ProductPaths: Equatable, Sendable {
    public var configDirectory: URL
    public var dataDirectory: URL

    public init(configDirectory: URL, dataDirectory: URL) {
        self.configDirectory = configDirectory
        self.dataDirectory = dataDirectory
    }

    public var trustStoreURL: URL {
        dataDirectory.appendingPathComponent("trusted-peers.json")
    }

    public var bindingStoreURL: URL {
        configDirectory.appendingPathComponent("pad-bindings.json")
    }

    public static var `default`: ProductPaths {
        let environment = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: NSHomeDirectory())
        #if os(macOS)
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let base = applicationSupport.appendingPathComponent("InkWand", isDirectory: true)
        return ProductPaths(configDirectory: base, dataDirectory: base)
        #else
        let configBase = environment["XDG_CONFIG_HOME"].map(URL.init(fileURLWithPath:)) ?? home.appendingPathComponent(".config")
        let dataBase = environment["XDG_DATA_HOME"].map(URL.init(fileURLWithPath:)) ?? home.appendingPathComponent(".local/share")
        return ProductPaths(
            configDirectory: configBase.appendingPathComponent("inkwand", isDirectory: true),
            dataDirectory: dataBase.appendingPathComponent("inkwand", isDirectory: true)
        )
        #endif
    }
}
