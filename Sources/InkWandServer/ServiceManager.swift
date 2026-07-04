#if os(Linux)
import Foundation

enum ServiceAction: String {
    case install
    case uninstall
}

struct ServiceInstallOptions {
    let port: UInt16
    let binaryPath: String
    let servicePath: String
    let udevRulePath: String
}

enum ServiceManager {
    static let defaultBinaryPath = "/usr/local/bin/InkWandServer"
    static let defaultServicePath = "/etc/systemd/system/inkwand-server.service"
    static let defaultUdevRulePath = "/etc/udev/rules.d/70-inkwand-uinput.rules"

    static func install(options: ServiceInstallOptions) throws {
        guard Privilege.requireRoot(commandDescription: "Service installation") else {
            return
        }

        let sourcePath = try currentExecutablePath()
        try copyExecutable(from: sourcePath, to: options.binaryPath)
        try writeFile(systemdUnit(binaryPath: options.binaryPath, port: options.port), to: options.servicePath)
        try writeFile(udevRule(), to: options.udevRulePath)

        _ = try? run("systemctl", ["daemon-reload"])
        _ = try? run("udevadm", ["control", "--reload-rules"])
        _ = try? run("udevadm", ["trigger", "--subsystem-match=misc"])

        print("Installed InkWandServer binary: \(options.binaryPath)")
        print("Installed systemd service: \(options.servicePath)")
        print("Installed udev rule: \(options.udevRulePath)")
        print("")
        print("Start now:")
        print("  sudo systemctl enable --now inkwand-server.service")
        print("")
        print("View logs:")
        print("  journalctl -u inkwand-server.service -f")
    }

    static func uninstall(options: ServiceInstallOptions) throws {
        guard Privilege.requireRoot(commandDescription: "Service removal") else {
            return
        }

        _ = try? run("systemctl", ["disable", "--now", "inkwand-server.service"])
        try removeFileIfExists(options.servicePath)
        try removeFileIfExists(options.udevRulePath)
        try removeFileIfExists(options.binaryPath)
        _ = try? run("systemctl", ["daemon-reload"])
        _ = try? run("udevadm", ["control", "--reload-rules"])

        print("Removed InkWandServer service, udev rule, and installed binary.")
    }

    private static func currentExecutablePath() throws -> String {
        let path = CommandLine.arguments[0]
        if path.hasPrefix("/") {
            return path
        }

        let currentDirectory = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentDirectory))
            .standardizedFileURL
            .path
    }

    private static func copyExecutable(from sourcePath: String, to destinationPath: String) throws {
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let destinationDirectory = destinationURL.deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: destinationDirectory, withIntermediateDirectories: true)

        try removeFileIfExists(destinationPath)
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationPath)
    }

    private static func writeFile(_ contents: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func removeFileIfExists(_ path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }

    private static func systemdUnit(binaryPath: String, port: UInt16) -> String {
        """
        [Unit]
        Description=InkWand iPad tablet server
        Documentation=https://github.com/
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=simple
        ExecStart=\(binaryPath) run --port \(port)
        Restart=on-failure
        RestartSec=2

        [Install]
        WantedBy=multi-user.target

        """
    }

    private static func udevRule() -> String {
        """
        KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
        """
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServerError.commandFailed(([executable] + arguments).joined(separator: " "), process.terminationStatus)
        }
    }
}
#endif
