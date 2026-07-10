import ArgumentParser
import Dispatch
import Foundation
import InkWandCore
#if (os(Linux) || os(macOS)) && canImport(SwiftCrossUI) && canImport(DefaultBackend)
import DefaultBackend
import SwiftCrossUI
#endif

struct ServerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "InkWandServer",
        abstract: "Receive Apple Pencil samples from InkWand over USB or Wi-Fi and expose a native desktop tablet.",
        subcommands: [RunCommand.self, FirewallCommand.self, AutostartCommand.self],
        defaultSubcommand: RunCommand.self
    )
}

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the InkWand tablet server."
    )

    @Option(help: "TCP port used for USB tunnel and Wi-Fi listener.")
    var port: UInt16 = 24817

    @Flag(help: "Print connection and event diagnostics.")
    var verbose = false

    @Flag(help: "Diagnostic: disable USB tunnel and USB connector loop.")
    var noUSB = false

    @Flag(help: "Diagnostic: disable Wi-Fi listener, Bonjour, and UDP discovery.")
    var noWiFi = false

    @Flag(help: "Allow one iPad to pair at startup and print the temporary pairing code.")
    var pair = false

    @Option(help: "Display name advertised to iPads.")
    var serverName = InkWandServerRuntime.defaultServerName

    mutating func run() throws {
        let runtime = InkWandServerRuntime(
            port: port,
            serverName: serverName,
            verbose: verbose,
            enableUSB: !noUSB,
            enableWiFi: !noWiFi
        )
        try runtime.start(pairing: pair)
        let shutdown = ShutdownCoordinator()

        shutdown.setCleanup {
            runtime.stop()
        }
        shutdown.installSignalHandlers()

        ServerLog.info("InkWandServer is ready. Open InkWand on the iPad when you want to draw.")
        ServerLog.info("Trusted iPads: \(runtime.trustedPeers.count). Config: \(ProductPaths.default.configDirectory.path)")
        ServerLog.info("Enabled transports: \(enabledTransportDescription). \(platformInputDetail)")
        let addresses = NetworkInterfaces.localIPv4Addresses()
        if addresses.isEmpty {
            ServerLog.info("No non-loopback IPv4 address detected for manual Wi-Fi connection.")
        } else {
            ServerLog.info("Manual Wi-Fi server IP candidates: \(addresses.joined(separator: ", "))")
        }
        if verbose {
            ServerLog.info("USB tunnel local port: \(port + 1) -> iPad port: \(port)")
        }

        dispatchMain()
    }

    private var enabledTransportDescription: String {
        switch (noUSB, noWiFi) {
        case (false, false):
            return "USB and Wi-Fi on port \(port)"
        case (true, false):
            return "Wi-Fi on port \(port)"
        case (false, true):
            return "USB on iPad port \(port)"
        case (true, true):
            return "none"
        }
    }

    private var platformInputDetail: String {
        #if os(Linux)
        return "On X11, InkWand will try to map virtual input devices to the full desktop during the first input events."
        #elseif os(macOS)
        return "On macOS, allow InkWandServer in Input Monitoring and Accessibility if prompted."
        #else
        return ""
        #endif
    }
}

struct FirewallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "firewall",
        abstract: "Install or remove local firewall rules for InkWand Wi-Fi mode.",
        subcommands: [FirewallInstallCommand.self, FirewallUninstallCommand.self]
    )
}

struct FirewallInstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Open the InkWand TCP/UDP port in ufw or firewalld."
    )

    @Option(help: "TCP/UDP port used by InkWand Wi-Fi mode.")
    var port: UInt16 = 24817

    mutating func run() throws {
        try FirewallManager.apply(.install, port: port)
    }
}

struct FirewallUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove the InkWand TCP/UDP firewall rules from ufw or firewalld."
    )

    @Option(help: "TCP/UDP port used by InkWand Wi-Fi mode.")
    var port: UInt16 = 24817

    mutating func run() throws {
        try FirewallManager.apply(.uninstall, port: port)
    }
}

struct AutostartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autostart",
        abstract: "Enable or disable launching the InkWand AppImage when the user signs in.",
        subcommands: [AutostartEnableCommand.self, AutostartDisableCommand.self, AutostartStatusCommand.self]
    )
}

struct AutostartEnableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Create a user autostart entry pointing at the current AppImage or executable."
    )

    @Option(help: "Executable or AppImage path to launch at sign-in.")
    var path: String?

    mutating func run() throws {
        let manager = AutostartManager(fileURL: AutostartManager.defaultFileURL())
        let appPath = path ?? ProcessInfo.processInfo.environment["APPIMAGE"] ?? CommandLine.arguments.first ?? "InkWandServer"
        try manager.enable(appImagePath: appPath)
        print("Launch at startup enabled for \(appPath)")
    }
}

struct AutostartDisableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Remove the InkWand user autostart entry."
    )

    mutating func run() throws {
        try AutostartManager(fileURL: AutostartManager.defaultFileURL()).disable()
        print("Launch at startup disabled.")
    }
}

struct AutostartStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Print the current InkWand autostart state."
    )

    @Option(help: "Expected executable or AppImage path.")
    var path: String?

    mutating func run() throws {
        let appPath = path ?? ProcessInfo.processInfo.environment["APPIMAGE"] ?? CommandLine.arguments.first ?? "InkWandServer"
        let state = AutostartManager(fileURL: AutostartManager.defaultFileURL()).state(expectedAppImagePath: appPath)
        switch state {
        case .disabled:
            print("Launch at startup: disabled")
        case let .enabled(path):
            print("Launch at startup: enabled (\(path))")
        case let .stale(path, expectedPath):
            print("Launch at startup: stale (\(path)); expected \(expectedPath)")
        }
    }
}

#if (os(Linux) || os(macOS)) && canImport(SwiftCrossUI) && canImport(DefaultBackend)
@main
struct InkWandServerApp: App {
    private static let runtime = InkWandServerRuntime()
    @State private var refreshID = 0
    @State private var autostartEnabled = false

    @Environment(\.openWindow) var openWindow

    init() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty {
            ServerCommand.main(arguments)
            Foundation.exit(0)
        }
        do {
            try Self.runtime.start()
        } catch {
            ServerLog.info("Failed to start InkWand Server: \(error)")
        }
    }

    var body: some Scene {
        Window("InkWand Server", id: "settings") {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("InkWand")
                            .font(.system(size: 30))
                        Text(serverHeadline)
                            .font(.system(size: 18))
                        Text(serverDetail)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect an iPad")
                            .font(.system(size: 18))
                        Text("Open InkWand on your iPad, tap this computer, then approve the request here.")
                        if Self.runtime.pendingPairingRequests.isEmpty {
                            Text("No iPad is asking to connect right now.")
                        } else {
                            ForEach(Self.runtime.pendingPairingRequests) { request in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(request.clientName)
                                        Text("Wants to connect. Expires in \(pairingSecondsRemaining(request)) seconds.")
                                    }
                                    Button("Reject") {
                                        Self.runtime.rejectPairingRequest(id: request.requestID)
                                        refresh()
                                    }
                                    Button("Accept") {
                                        Self.runtime.approvePairingRequest(id: request.requestID)
                                        refresh()
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Authorized iPads")
                            .font(.system(size: 18))
                        if Self.runtime.trustedPeers.isEmpty {
                            Text("No iPads have been authorized yet.")
                        } else {
                            ForEach(Self.runtime.trustedPeers) { peer in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peer.name)
                                        Text(peer.lastSeenAt == nil ? "Never connected" : "Previously connected")
                                    }
                                    Button("Revoke") {
                                        Self.runtime.revokePeer(id: peer.peerID)
                                        refresh()
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings")
                            .font(.system(size: 18))
                        Text("Computer name: \(Self.runtime.currentServerName)")
                        Text("Wi-Fi port: \(Self.runtime.currentPort)")
                        #if os(Linux)
                            Button(autostartEnabled ? "Disable launch at startup" : "Launch when system starts") {
                                setAutostart(enabled: !autostartEnabled)
                            }
                        #else
                            Text("Launch at startup is not available on macOS yet.")
                        #endif
                    }
                }
                .padding()
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 560, height: 620)

        StatusItem("InkWand", id: "inkwand-server", tooltip: "InkWand Server: \(Self.runtime.state.title)") {
            Text("InkWand Server")
            Text(serverHeadline)
            if Self.runtime.pendingPairingRequests.isEmpty {
                Text("No pending iPad requests")
            } else {
                Text("\(Self.runtime.pendingPairingRequests.count) iPad request pending")
                ForEach(Self.runtime.pendingPairingRequests) { request in
                    Text(request.clientName)
                    Button("Accept \(request.clientName)") {
                        Self.runtime.approvePairingRequest(id: request.requestID)
                        refresh()
                    }
                    Button("Reject \(request.clientName)") {
                        Self.runtime.rejectPairingRequest(id: request.requestID)
                        refresh()
                    }
                    Divider()
                }
            }
            Divider()
            Button("Open Settings") { openWindow(id: "settings") }
            Divider()
            #if os(Linux)
                Button(autostartEnabled ? "Disable launch at startup" : "Launch when system starts") {
                    setAutostart(enabled: !autostartEnabled)
                }
                Divider()
            #endif
            Button("Quit") {
                Self.runtime.stop()
                Foundation.exit(0)
            }
        } primaryAction: {
            openWindow(id: "settings")
        }
    }

    private var serverHeadline: String {
        switch Self.runtime.state {
        case .ready:
            return "Ready to connect an iPad"
        case .starting:
            return "Starting the tablet server"
        case .stopped:
            return "Server is stopped"
        case .failed:
            return "Setup needs attention"
        }
    }

    private var serverDetail: String {
        switch Self.runtime.state {
        case .ready:
            return "Keep this app open. InkWand will appear on iPads using the same Wi-Fi network."
        case .starting:
            return "Preparing virtual input devices and network discovery."
        case .stopped:
            return "Reopen the app to start the server."
        case let .failed(message):
            return message
        }
    }

    private func pairingSecondsRemaining(_ request: PendingPairingRequest) -> Int {
        max(0, Int(request.expiresAt.timeIntervalSinceNow.rounded(.up)))
    }

    private func refresh() {
        refreshID += 1
    }

    private func setAutostart(enabled: Bool) {
        do {
            let manager = AutostartManager(fileURL: AutostartManager.defaultFileURL())
            if enabled {
                let appPath = ProcessInfo.processInfo.environment["APPIMAGE"] ?? CommandLine.arguments[0]
                try manager.enable(appImagePath: appPath)
            } else {
                try manager.disable()
            }
            autostartEnabled = enabled
        } catch {
            ServerLog.info("Autostart failed: \(error)")
        }
        refresh()
    }
}
#else
@main
struct InkWandServerCLI {
    static func main() {
        ServerCommand.main()
    }
}
#endif
