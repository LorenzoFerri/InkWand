import ArgumentParser
import Dispatch
import Foundation
import InkWandCore

struct ServerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "InkWandServer",
        abstract: "Receive Apple Pencil samples from InkWand over USB or Wi-Fi and expose a native Linux uinput pen tablet.",
        subcommands: [RunCommand.self, FirewallCommand.self, ServiceCommand.self],
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

    mutating func run() throws {
        guard port < UInt16.max else {
            throw ValidationError("--port must be lower than 65535 because InkWand uses the next local port for USB tunneling.")
        }

        guard !noUSB || !noWiFi else {
            throw ValidationError("At least one transport must be enabled.")
        }

        let usbLocalPort = port + 1
        let mapper = TabletMapper()
        let device = try UInputPenDevice(maxX: mapper.maxX, maxY: mapper.maxY, maxPressure: mapper.maxPressure)
        let touchDevice = try UInputTouchDevice(maxX: mapper.maxX, maxY: mapper.maxY)
        let padDevice = try UInputPadDevice()
        let coordinator = TabletSessionCoordinator(
            device: device,
            padDevice: padDevice,
            touchDevice: touchDevice,
            verbose: verbose
        )
        let wifiListener = noWiFi ? nil : WiFiTabletListener(port: port, verbose: verbose, coordinator: coordinator)
        let udpDiscovery = noWiFi ? nil : UDPDiscoveryResponder(port: port, verbose: verbose)
        let shutdown = ShutdownCoordinator()

        let cleanup = {
            coordinator.releaseAndDestroy()
            wifiListener?.stop()
            udpDiscovery?.stop()
        }

        defer {
            cleanup()
        }

        try wifiListener?.start()
        udpDiscovery?.start()
        let tunnel = noUSB ? nil : USBMuxTunnel.startBestEffort(localPort: usbLocalPort, devicePort: port, verbose: verbose)
        let publisher = noWiFi ? nil : ServicePublisher.startBestEffort(port: port, verbose: verbose)
        if !noUSB {
            startUSBConnectorLoop(port: usbLocalPort, verbose: verbose, coordinator: coordinator)
        }

        shutdown.setCleanup {
            cleanup()
            publisher?.stop()
            tunnel?.stop()
        }
        shutdown.installSignalHandlers()

        defer {
            publisher?.stop()
            tunnel?.stop()
        }

        ServerLog.info("InkWandServer is ready. Open InkWand on the iPad when you want to draw.")
        ServerLog.info("Enabled transports: \(enabledTransportDescription). On X11, InkWand will try to map virtual input devices to the full desktop during the first input events.")
        let addresses = NetworkInterfaces.localIPv4Addresses()
        if addresses.isEmpty {
            ServerLog.info("No non-loopback IPv4 address detected for manual Wi-Fi connection.")
        } else {
            ServerLog.info("Manual Wi-Fi server IP candidates: \(addresses.joined(separator: ", "))")
        }
        if verbose {
            ServerLog.info("USB tunnel local port: \(usbLocalPort) -> iPad port: \(port)")
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

    private func startUSBConnectorLoop(port: UInt16, verbose: Bool, coordinator: TabletSessionCoordinator) {
        DispatchQueue.global(qos: .userInitiated).async {
            var lastWaitingMessage = Date.distantPast
            var retryDelay = 2.0
            let maxRetryDelay = 30.0

            while true {
                let client = TabletClient(host: "127.0.0.1", port: port, verbose: false)

                do {
                    try client.connect()
                    let activated = coordinator.runSession(client, transport: "USB")
                    if activated {
                        retryDelay = 2.0
                    } else {
                        Thread.sleep(forTimeInterval: retryDelay)
                        retryDelay = min(retryDelay * 1.8, maxRetryDelay)
                    }
                } catch {
                    let now = Date()
                    if now.timeIntervalSince(lastWaitingMessage) >= 5 {
                        ServerLog.info("Waiting for USB InkWand connection on 127.0.0.1:\(port)...")
                        if verbose {
                            ServerLog.info("last USB state: \(error)")
                        }
                        lastWaitingMessage = now
                    }
                    Thread.sleep(forTimeInterval: retryDelay)
                    retryDelay = min(retryDelay * 1.8, maxRetryDelay)
                }
            }
        }
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

struct ServiceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Install or remove InkWandServer as a systemd service.",
        subcommands: [ServiceInstallCommand.self, ServiceUninstallCommand.self]
    )
}

struct ServiceInstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the current InkWandServer binary, systemd service, and input udev rule."
    )

    @Option(help: "TCP/UDP port used by InkWand Wi-Fi mode.")
    var port: UInt16 = 24817

    @Option(help: "Destination path for the installed server binary.")
    var binaryPath = ServiceManager.defaultBinaryPath

    @Option(help: "Destination path for the systemd unit file.")
    var servicePath = ServiceManager.defaultServicePath

    @Option(help: "Destination path for the input udev rule.")
    var udevRulePath = ServiceManager.defaultUdevRulePath

    mutating func run() throws {
        try ServiceManager.install(
            options: ServiceInstallOptions(
                port: port,
                binaryPath: binaryPath,
                servicePath: servicePath,
                udevRulePath: udevRulePath
            )
        )
    }
}

struct ServiceUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Disable and remove the InkWandServer systemd service, input udev rule, and installed binary."
    )

    @Option(help: "TCP/UDP port used by InkWand Wi-Fi mode.")
    var port: UInt16 = 24817

    @Option(help: "Path of the installed server binary.")
    var binaryPath = ServiceManager.defaultBinaryPath

    @Option(help: "Path of the systemd unit file.")
    var servicePath = ServiceManager.defaultServicePath

    @Option(help: "Path of the input udev rule.")
    var udevRulePath = ServiceManager.defaultUdevRulePath

    mutating func run() throws {
        try ServiceManager.uninstall(
            options: ServiceInstallOptions(
                port: port,
                binaryPath: binaryPath,
                servicePath: servicePath,
                udevRulePath: udevRulePath
            )
        )
    }
}

ServerCommand.main()
