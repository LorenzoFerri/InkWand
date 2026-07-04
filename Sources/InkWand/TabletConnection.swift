#if canImport(Network) && canImport(UIKit)
import Foundation
import Network
import UIKit
import InkWandCore
#if canImport(Darwin)
import Darwin
#endif

enum TabletConnectionMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case usb = "USB"
    case wifi = "Wi-Fi"

    var id: String { rawValue }
}

enum TabletConnectionState: String {
    case searching = "Searching"
    case waiting = "Waiting"
    case connecting = "Connecting"
    case connected = "Connected"
}

private enum ActiveTransport: String {
    case usb = "USB"
    case wifi = "Wi-Fi"
}

final class TabletConnection: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: TabletConnectionState = .waiting
    @Published private(set) var activeTransportLabel: String = "None"
    @Published private(set) var detail: String = ""
    @Published private(set) var tool: PencilTool = .pen
    @Published private(set) var lastPressure: Double = 0
    @Published private(set) var lastTiltDegrees: Double = 0
    @Published var mode: TabletConnectionMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeDefaultsKey)
            restartTransports()
        }
    }

    private static let modeDefaultsKey = "InkWand.ConnectionMode"

    private let queue = DispatchQueue(label: "inkwand.tablet.connection")
    private var usbListener: NWListener?
    private var wifiBrowser: NWBrowser?
    private var udpDiscoverySource: DispatchSourceRead?
    private var udpDiscoveryTimer: DispatchSourceTimer?
    private var udpDiscoveryFD: Int32 = -1
    private var connection: NWConnection?
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private var isCancellingTimedOutConnection = false
    private var activeTransport: ActiveTransport?
    private var didPublishConnected = false
    private var pendingWiFiEndpoint: NWEndpoint?
    private var isWiFiConnecting = false
    private var canvasSize: CGSize = .zero
    private var currentTool: PencilTool = .pen
    private let deviceName = "iPad"
    private let port: UInt16

    init(port: UInt16 = 24817) {
        self.port = port
        let storedMode = UserDefaults.standard.string(forKey: Self.modeDefaultsKey)
        self.mode = storedMode.flatMap(TabletConnectionMode.init(rawValue:)) ?? .auto
        restartTransports()
    }

    deinit {
        queue.sync {
            connection?.cancel()
            usbListener?.cancel()
            wifiBrowser?.cancel()
            stopUDPDiscovery()
        }
    }

    func updateCanvasSize(_ size: CGSize) {
        queue.async {
            self.canvasSize = size
            self.sendHello()
        }
    }

    func send(_ sample: PencilSample) {
        publishStylusTelemetry(from: sample)

        queue.async {
            guard self.connection != nil else { return }
            if let activeTransport = self.activeTransport, !self.didPublishConnected {
                self.didPublishConnected = true
                self.publishState(.connected, transport: activeTransport.rawValue, detail: "")
            }
            self.sendMessage(.sample(sample))
        }
    }

    private func publishStylusTelemetry(from sample: PencilSample) {
        let pressure = max(0, min(sample.pressure, 1))
        let tilt = sample.altitude.map { altitude in
            max(0, min((.pi / 2 - altitude) * 180 / .pi, 90))
        } ?? 0

        DispatchQueue.main.async {
            self.lastPressure = sample.phase == .ended || sample.phase == .cancelled ? 0 : pressure
            self.lastTiltDegrees = sample.phase == .ended || sample.phase == .cancelled ? 0 : tilt
        }
    }

    func setMode(_ mode: TabletConnectionMode) {
        self.mode = mode
    }

    func toggleTool() {
        queue.async {
            let nextTool: PencilTool = self.currentTool == .pen ? .eraser : .pen
            self.currentTool = nextTool
            self.sendMessage(.tool(nextTool))

            DispatchQueue.main.async {
                self.tool = nextTool
            }
        }
    }

    func sendPadAction(_ action: PadAction) {
        queue.async {
            self.sendMessage(.pad(action))
        }
    }

    private func restartTransports() {
        queue.async {
            self.connection?.cancel()
            self.connection = nil
            self.connectionTimeoutWorkItem?.cancel()
            self.connectionTimeoutWorkItem = nil
            self.isCancellingTimedOutConnection = false
            self.activeTransport = nil
            self.didPublishConnected = false
            self.isWiFiConnecting = false
            self.pendingWiFiEndpoint = nil
            self.usbListener?.cancel()
            self.usbListener = nil
            self.wifiBrowser?.cancel()
            self.wifiBrowser = nil
            self.stopUDPDiscovery()

            self.publishState(self.mode == .wifi ? .searching : .waiting, transport: "None", detail: "")

            if self.mode == .auto || self.mode == .usb {
                self.startUSBListener()
            }

            if self.mode == .auto || self.mode == .wifi {
                self.startWiFiBrowser()
                self.startUDPDiscovery()
            }
        }
    }

    private func startUSBListener() {
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] newConnection in
                self?.acceptUSB(newConnection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    if self.connection == nil, self.activeTransport == nil {
                        self.publishState(.waiting, transport: "None", detail: "")
                    }
                    print("InkWand USB waiting on port \(self.port)")
                case let .failed(error):
                    print("InkWand USB listener failed: \(error); restarting")
                    self.publishState(.waiting, detail: "USB listener failed")
                    self.restartUSBListenerSoon()
                default:
                    break
                }
            }
            listener.start(queue: queue)
            usbListener = listener
        } catch {
            print("InkWand USB listener could not start: \(error)")
            publishState(.waiting, detail: "USB listener unavailable")
        }
    }

    private func startWiFiBrowser() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_inkwand._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                self.publishState(self.connection == nil ? .searching : .connected, detail: "")
            case let .failed(error):
                print("InkWand Wi-Fi browser failed: \(error); restarting")
                self.publishState(.searching, transport: "None", detail: "Wi-Fi discovery failed")
                self.restartWiFiBrowserSoon()
            case let .waiting(error):
                print("InkWand Wi-Fi browser waiting: \(error)")
                self.publishState(.searching, detail: "Wi-Fi discovery waiting")
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            guard self.connection == nil, !self.isWiFiConnecting else { return }
            guard self.mode == .auto || self.mode == .wifi else { return }
            guard let endpoint = results.first?.endpoint else { return }

            self.connectWiFi(to: endpoint)
        }

        browser.start(queue: queue)
        wifiBrowser = browser
        publishState(.searching, detail: "")
    }

    private func startUDPDiscovery() {
        #if canImport(Darwin)
        guard udpDiscoveryFD < 0 else { return }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            publishState(.searching, detail: "UDP discovery unavailable")
            return
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var bindAddress = sockaddr_in()
        bindAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddress.sin_family = sa_family_t(AF_INET)
        bindAddress.sin_port = 0
        bindAddress.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &bindAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            Darwin.close(fd)
            publishState(.searching, detail: "UDP discovery bind failed")
            return
        }

        udpDiscoveryFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleUDPDiscoveryRead()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        udpDiscoverySource = source

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.sendUDPDiscoveryProbe()
        }
        timer.resume()
        udpDiscoveryTimer = timer
        #endif
    }

    private func stopUDPDiscovery() {
        udpDiscoveryTimer?.cancel()
        udpDiscoveryTimer = nil
        udpDiscoverySource?.cancel()
        udpDiscoverySource = nil
        udpDiscoveryFD = -1
    }

    private func acceptUSB(_ newConnection: NWConnection) {
        guard mode == .auto || mode == .usb else {
            newConnection.cancel()
            return
        }

        guard connection == nil else {
            newConnection.cancel()
            return
        }

        publishState(.connecting, transport: ActiveTransport.usb.rawValue, detail: "")
        accept(newConnection, transport: .usb)
    }

    private func connectWiFi(to endpoint: NWEndpoint) {
        guard connection == nil, !isWiFiConnecting else { return }

        isWiFiConnecting = true
        pendingWiFiEndpoint = endpoint
        publishState(.connecting, transport: "Wi-Fi", detail: "Bonjour \(endpoint)")

        let newConnection = NWConnection(to: endpoint, using: .tcp)
        accept(newConnection, transport: .wifi)
    }

    private func connectWiFi(host: String, port: UInt16) {
        guard connection == nil, !isWiFiConnecting else { return }
        guard mode == .auto || mode == .wifi else { return }

        connectWiFi(host: host, port: port, detail: "UDP \(host):\(port)", requireWiFiMode: true)
    }

    private func connectWiFi(host: String, port: UInt16, detail: String, requireWiFiMode: Bool) {
        guard connection == nil, !isWiFiConnecting else { return }
        guard !requireWiFiMode || mode == .auto || mode == .wifi else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }

        isWiFiConnecting = true
        publishState(.connecting, transport: "Wi-Fi", detail: detail)

        let newConnection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        accept(newConnection, transport: .wifi)
    }

    private func accept(_ newConnection: NWConnection, transport: ActiveTransport) {
        connection = newConnection
        activeTransport = transport
        didPublishConnected = false
        startConnectionTimeout(for: newConnection, transport: transport)

        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let self, let newConnection else { return }

            switch state {
            case .setup:
                self.publishState(.connecting, transport: transport.rawValue, detail: "\(transport.rawValue) setup")
            case .preparing:
                self.publishState(.connecting, transport: transport.rawValue, detail: "\(transport.rawValue) preparing")
            case let .waiting(error):
                print("InkWand \(transport.rawValue) connection waiting: \(error)")
                self.publishState(.connecting, transport: transport.rawValue, detail: "\(transport.rawValue) waiting")
            case .ready:
                self.connectionTimeoutWorkItem?.cancel()
                self.connectionTimeoutWorkItem = nil
                self.isWiFiConnecting = false
                self.didPublishConnected = true
                self.sendHello()
                self.publishState(.connected, transport: transport.rawValue, detail: "")
            case .cancelled:
                if self.isCancellingTimedOutConnection {
                    self.isCancellingTimedOutConnection = false
                } else {
                    self.invalidateConnection(newConnection)
                }
            case let .failed(error):
                self.connectionTimeoutWorkItem?.cancel()
                self.connectionTimeoutWorkItem = nil
                print("InkWand \(transport.rawValue) connection failed: \(error)")
                self.publishState(.searching, detail: "\(transport.rawValue) connection failed")
                self.invalidateConnection(newConnection)
            default:
                break
            }
        }

        newConnection.start(queue: queue)
    }

    private func startConnectionTimeout(for newConnection: NWConnection, transport: ActiveTransport) {
        connectionTimeoutWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self, weak newConnection] in
            guard let self, let newConnection else { return }
            guard self.connection === newConnection else { return }

            print("InkWand \(transport.rawValue) connection timed out")
            self.connection = nil
            self.activeTransport = nil
            self.didPublishConnected = false
            self.isWiFiConnecting = false
            self.connectionTimeoutWorkItem = nil
            self.isCancellingTimedOutConnection = true
            newConnection.cancel()
            self.publishState(.searching, transport: "None", detail: "\(transport.rawValue) TCP timeout")
        }

        connectionTimeoutWorkItem = item
        queue.asyncAfter(deadline: .now() + 5.0, execute: item)
    }

    private func invalidateConnection(_ staleConnection: NWConnection? = nil) {
        guard let current = connection else {
            isWiFiConnecting = false
            publishIdleState()
            return
        }

        if let staleConnection, current !== staleConnection {
            return
        }

        connection = nil
        activeTransport = nil
        didPublishConnected = false
        isWiFiConnecting = false
        isCancellingTimedOutConnection = false
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        current.cancel()
        publishIdleState()
    }

    private func publishIdleState() {
        switch mode {
        case .auto:
            publishState(.searching, transport: "None", detail: "")
        case .usb:
            publishState(.waiting, transport: "None", detail: "")
        case .wifi:
            publishState(.searching, transport: "None", detail: "")
        }
    }

    private func restartUSBListenerSoon() {
        usbListener?.cancel()
        usbListener = nil

        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.mode == .auto || self.mode == .usb else { return }
            self.startUSBListener()
        }
    }

    private func restartWiFiBrowserSoon() {
        wifiBrowser?.cancel()
        wifiBrowser = nil
        isWiFiConnecting = false

        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.mode == .auto || self.mode == .wifi else { return }
            self.startWiFiBrowser()
        }
    }

    #if canImport(Darwin)
    private func sendUDPDiscoveryProbe() {
        guard udpDiscoveryFD >= 0, connection == nil, !isWiFiConnecting else { return }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_BROADCAST)

        let payload = Array("INKWAND_DISCOVER_V1\n".utf8)
        _ = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.sendto(udpDiscoveryFD, payload, payload.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private func handleUDPDiscoveryRead() {
        guard udpDiscoveryFD >= 0, connection == nil, !isWiFiConnecting else { return }

        var buffer = [UInt8](repeating: 0, count: 512)
        var sender = sockaddr_in()
        var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &sender) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.recvfrom(udpDiscoveryFD, &buffer, buffer.count, 0, sockaddrPointer, &senderLength)
            }
        }

        guard count > 0 else { return }

        let response = String(decoding: buffer.prefix(Int(count)), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = response.split(separator: " ")
        guard parts.count == 2, parts[0] == "INKWAND_SERVER_V1", let discoveredPort = UInt16(parts[1]) else {
            return
        }

        var senderAddress = sender.sin_addr
        var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &senderAddress, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return
        }

        let ipBytes = ipBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        connectWiFi(host: String(decoding: ipBytes, as: UTF8.self), port: discoveredPort)
    }
    #endif

    private func sendHello() {
        guard connection != nil, canvasSize.width > 0, canvasSize.height > 0 else { return }
        sendMessage(
            .hello(
                TabletHello(
                    protocolVersion: 1,
                    canvasWidth: Double(canvasSize.width),
                    canvasHeight: Double(canvasSize.height),
                    deviceName: deviceName
                )
            )
        )
        sendMessage(.tool(currentTool))
    }

    private func sendMessage(_ message: InkMessage) {
        guard let connection else { return }

        do {
            let data = try JSONLineCodec.encode(message)
            connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self else { return }

                if let error {
                    print("InkWand send failed: \(error)")
                    if let connection {
                        self.queue.async {
                            self.invalidateConnection(connection)
                        }
                    }
                }
            })
        } catch {
            print("InkWand encode failed: \(error)")
        }
    }

    private func publishState(_ state: TabletConnectionState, transport: String? = nil, detail: String? = nil) {
        DispatchQueue.main.async {
            self.state = state
            if let transport {
                self.activeTransportLabel = transport
            }
            if let detail {
                self.detail = detail
            }
        }
    }
}
#endif
