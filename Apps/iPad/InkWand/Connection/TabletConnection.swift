import Combine
import Darwin
import Foundation
import InkWandCore
import Network
import UIKit

enum TabletConnectionMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case usb = "USB"
    case wifi = "Wi-Fi"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .auto:
            return "wand.and.rays"
        case .usb:
            return "cable.connector"
        case .wifi:
            return "wifi"
        }
    }
}

enum TabletConnectionState: String {
    case searching = "Searching"
    case waiting = "Waiting"
    case connecting = "Connecting"
    case pairing = "Pairing"
    case authenticating = "Authenticating"
    case connected = "Connected"
    case failed = "Needs attention"
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
    @Published private(set) var discoveredServers: [ServerAdvertisement] = []
    @Published private(set) var trustedServers: [TrustedPeer] = []
    @Published var selectedServerID: String? {
        didSet {
            UserDefaults.standard.set(selectedServerID, forKey: Self.selectedServerDefaultsKey)
            guard !isPersistingSelectedServerWithoutRestart else { return }
            restartTransports()
        }
    }
    @Published var mode: TabletConnectionMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeDefaultsKey)
            restartTransports()
        }
    }

    private static let modeDefaultsKey = "InkWand.ConnectionMode"
    private static let selectedServerDefaultsKey = "InkWand.SelectedServerID"

    private let queue = DispatchQueue(label: "inkwand.tablet.connection", qos: .userInteractive)
    private let trustStore = TabletTrustStore()
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
    private var pendingWiFiServer: ServerAdvertisement?
    private var activeServer: ServerAdvertisement?
    private var pendingAuthHandshake: SecureHandshake?
    private var pendingPairingHandshake: SecureHandshake?
    private var secureSession: SecureSession?
    private var receiveBuffer = Data()
    private var isPersistingSelectedServerWithoutRestart = false
    private var isWiFiConnecting = false
    private var canvasSize: CGSize = .zero
    private var currentTool: PencilTool = .pen
    private let deviceName = "iPad"
    private let port: UInt16

    init(port: UInt16 = 24817) {
        self.port = port
        let storedMode = UserDefaults.standard.string(forKey: Self.modeDefaultsKey)
        self.mode = storedMode.flatMap(TabletConnectionMode.init(rawValue:)) ?? .auto
        self.selectedServerID = UserDefaults.standard.string(forKey: Self.selectedServerDefaultsKey)
        refreshTrustedServers()
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
        send([sample], publishTelemetry: true)
    }

    func send(_ samples: [PencilSample], publishTelemetry: Bool = true) {
        guard !samples.isEmpty else { return }

        if publishTelemetry, let sample = samples.last {
            publishStylusTelemetry(from: sample)
        }

        queue.async {
            guard self.connection != nil else { return }
            if let activeTransport = self.activeTransport, !self.didPublishConnected {
                self.didPublishConnected = true
                self.publishState(.connected, transport: activeTransport.rawValue, detail: "")
            }
            for sample in samples {
                self.sendMessage(.sample(sample))
            }
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

    func selectServer(_ server: ServerAdvertisement) {
        selectedServerID = server.serverID
    }

    func connectToServer(_ server: ServerAdvertisement) {
        selectedServerID = trustedPeer(for: server)?.peerID ?? server.serverID
    }

    func retrySelectedServer() {
        restartTransports()
    }

    func forgetSelectedServer() {
        guard let selectedServerID else { return }
        trustStore.revoke(serverID: selectedServerID)
        self.selectedServerID = nil
        refreshTrustedServers()
    }

    func forgetTrustedServer(id: String) {
        trustStore.revoke(serverID: id)
        if selectedServerID == id {
            selectedServerID = nil
        }
        refreshTrustedServers()
    }

    func forgetAllTrustedServers() {
        trustStore.revokeAll()
        selectedServerID = nil
        refreshTrustedServers()
    }

    func isTrusted(_ server: ServerAdvertisement) -> Bool {
        trustedPeer(for: server) != nil
    }

    func trustedServerName(id: String) -> String? {
        trustStore.server(id: id)?.name
    }

    private func trustedPeer(for server: ServerAdvertisement) -> TrustedPeer? {
        trustStore.server(id: server.serverID) ?? trustStore.server(named: server.name)
    }

    func trust(serverID: String, name: String, token: String) {
        trustStore.trust(serverID: serverID, name: name, token: token)
        refreshTrustedServers()
    }

    func reconnectToTrustedServer(id: String) {
        selectedServerID = id
    }

    func requestPairingWithActiveServer() {
        sendPairingRequest(code: "")
    }

    func pairWithActiveServer(code: String) {
        sendPairingRequest(code: code)
    }

    private func sendPairingRequest(code: String) {
        queue.async {
            guard let activeServer = self.activeServer else {
                self.publishState(.searching, detail: "Choose a computer first")
                return
            }
            let handshake = try? SecureChannel.makeHandshake()
            self.pendingPairingHandshake = handshake
            let serverID = activeServer.serverID.hasPrefix("bonjour:") ? "" : activeServer.serverID
            self.sendMessage(
                .pairingRequest(
                    PairingRequest(
                        serverID: serverID,
                        clientID: self.trustStore.clientID,
                        clientName: self.trustStore.clientName,
                        code: code,
                        clientPublicKey: handshake?.publicKeyString,
                        clientNonce: handshake?.nonceString
                    )
                )
            )
            self.publishState(
                .pairing,
                transport: self.activeTransport?.rawValue ?? "Wi-Fi",
                detail: code.isEmpty ? "Approve the request on your computer" : "Checking pairing code"
            )
        }
    }

    private func refreshTrustedServers() {
        DispatchQueue.main.async {
            self.trustedServers = self.trustStore.allServers()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    @MainActor
    func setTool(_ nextTool: PencilTool) {
        guard currentTool != nextTool else { return }
        currentTool = nextTool
        tool = nextTool

        queue.async {
            self.sendMessage(.tool(nextTool))
        }
    }

    func toggleTool() {
        Task { @MainActor in
            setTool(currentTool == .pen ? .eraser : .pen)
        }
    }

    func sendPadAction(_ action: PadAction) {
        queue.async {
            self.sendMessage(.pad(action))
        }
    }

    func cancelInputState() {
        queue.async {
            self.sendMessage(.cancel)
        }
    }

    func sendTouchFrame(_ touches: [TouchSample]) {
        guard !touches.isEmpty else { return }

        queue.async {
            guard self.connection != nil else { return }
            self.sendMessage(.touchFrame(touches))
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
            self.pendingWiFiServer = nil
            self.activeServer = nil
            self.receiveBuffer.removeAll()
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
            let listener = try NWListener(using: Self.lowLatencyTCPParameters(), on: NWEndpoint.Port(rawValue: port)!)
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
        let browser = NWBrowser(for: descriptor, using: Self.lowLatencyTCPParameters())

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
            let indexedResults = results.compactMap { result -> (NWBrowser.Result, ServerAdvertisement)? in
                guard let advertisement = self.bonjourAdvertisement(for: result) else { return nil }
                return (result, advertisement)
            }
            indexedResults.forEach { _, advertisement in
                self.rememberDiscoveredServer(advertisement)
            }
            guard let selectedServerID = self.selectedServerID else { return }
            guard let match = indexedResults.first(where: { _, advertisement in
                advertisement.serverID == selectedServerID || self.trustStore.server(id: selectedServerID)?.name == advertisement.name
            }) else { return }
            let selectedAdvertisement = self.trustStore.server(id: selectedServerID).map { trusted in
                ServerAdvertisement(
                    serverID: trusted.peerID,
                    name: trusted.name,
                    port: match.1.port,
                    pairingAvailable: match.1.pairingAvailable
                )
            } ?? match.1
            self.connectWiFi(to: match.0.endpoint, server: selectedAdvertisement)
        }

        browser.start(queue: queue)
        wifiBrowser = browser
        publishState(.searching, detail: "")
    }

    private func startUDPDiscovery() {
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

    private func connectWiFi(to endpoint: NWEndpoint, server: ServerAdvertisement? = nil) {
        guard connection == nil, !isWiFiConnecting else { return }

        isWiFiConnecting = true
        pendingWiFiEndpoint = endpoint
        pendingWiFiServer = server
        publishState(.connecting, transport: "Wi-Fi", detail: "Bonjour \(endpoint)")

        let newConnection = NWConnection(to: endpoint, using: Self.lowLatencyTCPParameters())
        accept(newConnection, transport: .wifi)
    }

    private func connectWiFi(host: String, port: UInt16, server: ServerAdvertisement? = nil) {
        guard connection == nil, !isWiFiConnecting else { return }
        guard mode == .auto || mode == .wifi else { return }

        connectWiFi(host: host, port: port, detail: "UDP \(host):\(port)", requireWiFiMode: true, server: server)
    }

    private func connectWiFi(host: String, port: UInt16, detail: String, requireWiFiMode: Bool, server: ServerAdvertisement? = nil) {
        guard connection == nil, !isWiFiConnecting else { return }
        guard !requireWiFiMode || mode == .auto || mode == .wifi else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }

        isWiFiConnecting = true
        pendingWiFiServer = server
        publishState(.connecting, transport: "Wi-Fi", detail: detail)

        let newConnection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: Self.lowLatencyTCPParameters())
        accept(newConnection, transport: .wifi)
    }

    private func bonjourAdvertisement(for result: NWBrowser.Result) -> ServerAdvertisement? {
        switch result.endpoint {
        case let .service(name, type, domain, _):
            guard type == "_inkwand._tcp" else { return nil }
            return ServerAdvertisement(
                serverID: "bonjour:\(name).\(type).\(domain)",
                name: name.isEmpty ? "InkWand Server" : name,
                port: port,
                pairingAvailable: true
            )
        default:
            return nil
        }
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
                self.activeServer = self.pendingWiFiServer
                self.pendingWiFiServer = nil
                self.startReceiveLoop(on: newConnection)
                let sentAuthentication = self.sendAuthenticationIfNeeded()
                self.sendHello()
                if sentAuthentication {
                    self.publishState(.authenticating, transport: transport.rawValue, detail: "Checking trusted computer")
                } else if self.activeServer != nil {
                    self.requestPairingWithActiveServer()
                } else {
                    self.publishState(.connected, transport: transport.rawValue, detail: "")
                }
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
        pendingAuthHandshake = nil
        pendingPairingHandshake = nil
        secureSession = nil
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

    private func sendUDPDiscoveryProbe() {
        guard udpDiscoveryFD >= 0, connection == nil, !isWiFiConnecting else { return }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_BROADCAST)

        let payload = Array("\(InkWandDiscoveryProtocol.request)\n".utf8)
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
        let discoveredPort: UInt16
        let discoveredServer: ServerAdvertisement?
        if parts.count >= 2, parts[0] == Substring(InkWandDiscoveryProtocol.response),
           let payloadStart = response.firstIndex(of: "{"),
           let data = String(response[payloadStart...]).data(using: .utf8),
           let advertisement = try? JSONDecoder().decode(ServerAdvertisement.self, from: data) {
            discoveredPort = advertisement.port
            discoveredServer = advertisement
            rememberDiscoveredServer(advertisement)
        } else {
            return
        }

        var senderAddress = sender.sin_addr
        var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &senderAddress, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return
        }

        let ipBytes = ipBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let host = String(decoding: ipBytes, as: UTF8.self)
        if let discoveredServer, let selectedServerID,
           !selectedServerID.hasPrefix("bonjour:"),
           selectedServerID != discoveredServer.serverID {
            return
        }
        if let discoveredServer, selectedServerID == nil, trustStore.server(id: discoveredServer.serverID) == nil {
            return
        }

        connectWiFi(host: host, port: discoveredPort, server: discoveredServer)
    }

    private func rememberDiscoveredServer(_ server: ServerAdvertisement) {
        DispatchQueue.main.async {
            var servers = self.discoveredServers.filter { $0.serverID != server.serverID }
            servers.append(server)
            self.discoveredServers = servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    @discardableResult
    private func sendAuthenticationIfNeeded() -> Bool {
        guard let activeServer, let trusted = trustStore.server(id: activeServer.serverID) else { return false }
        let handshake = try? SecureChannel.makeHandshake()
        pendingAuthHandshake = handshake
        let proof = handshake.flatMap {
            try? SecureChannel.authProof(
                token: trusted.trustToken,
                serverID: activeServer.serverID,
                clientID: trustStore.clientID,
                publicKey: $0.publicKeyString,
                nonce: $0.nonceString
            )
        }
        sendMessage(
            .authRequest(
                AuthRequest(
                    serverID: activeServer.serverID,
                    clientID: trustStore.clientID,
                    clientName: trustStore.clientName,
                    trustToken: proof == nil ? trusted.trustToken : "",
                    clientPublicKey: handshake?.publicKeyString,
                    clientNonce: handshake?.nonceString,
                    authProof: proof
                )
            )
        )
        return true
    }

    private func startReceiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            self.queue.async {
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.processReceiveBuffer()
                }
                if let error {
                    print("InkWand receive failed: \(error)")
                    self.invalidateConnection(connection)
                    return
                }
                if isComplete {
                    self.invalidateConnection(connection)
                    return
                }
                if self.connection === connection {
                    self.startReceiveLoop(on: connection)
                }
            }
        }
    }

    private func processReceiveBuffer() {
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer.prefix(through: newline)
            receiveBuffer.removeSubrange(...newline)
            guard let message = try? JSONLineCodec.decodeLine(Data(line)) else { continue }
            if case let .encrypted(envelope) = message {
                guard let secureSession,
                      let decrypted = try? secureSession.decrypt(envelope) else {
                    publishState(.failed, detail: "Encrypted message could not be opened")
                    invalidateConnection()
                    return
                }
                handleServerMessage(decrypted)
            } else {
                handleServerMessage(message)
            }
        }
    }

    private func handleServerMessage(_ message: InkMessage) {
        switch message {
        case let .authResponse(response):
            if !response.accepted {
                publishState(.failed, detail: response.error ?? "Authentication rejected")
                invalidateConnection()
            } else {
                if let handshake = pendingAuthHandshake,
                   let serverPublicKey = response.serverPublicKey,
                   let serverNonce = response.serverNonce,
                   let activeServer,
                   let trusted = trustStore.server(id: activeServer.serverID) {
                    secureSession = try? SecureChannel.makeClientSession(
                        handshake: handshake,
                        serverPublicKey: serverPublicKey,
                        clientNonce: handshake.nonceString,
                        serverNonce: serverNonce,
                        token: trusted.trustToken,
                        context: "InkWand auth v1|\(activeServer.serverID)|\(trustStore.clientID)"
                    )
                }
                pendingAuthHandshake = nil
                publishState(.connected, detail: "")
            }

        case let .pairingResponse(response):
            guard response.accepted else {
                publishState(.failed, detail: response.error ?? "Pairing rejected")
                invalidateConnection()
                return
            }
            let token: String?
            if let encryptedTrustToken = response.encryptedTrustToken,
               let handshake = pendingPairingHandshake,
               let serverPublicKey = response.serverPublicKey,
               let serverNonce = response.serverNonce,
               let envelopeData = encryptedTrustToken.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(EncryptedMessage.self, from: envelopeData),
               let session = try? SecureChannel.makeClientSession(
                    handshake: handshake,
                    serverPublicKey: serverPublicKey,
                    clientNonce: handshake.nonceString,
                    serverNonce: serverNonce,
                    token: nil,
                    context: "InkWand pairing v1|\(response.serverID)|\(trustStore.clientID)"
               ),
               let tokenData = try? session.decryptData(envelope),
               let decryptedToken = String(data: tokenData, encoding: .utf8) {
                secureSession = session
                token = decryptedToken
            } else {
                token = response.trustToken
            }
            pendingPairingHandshake = nil
            guard let token else {
                publishState(.failed, detail: "Pairing response was not encrypted correctly")
                invalidateConnection()
                return
            }
            trustStore.trust(serverID: response.serverID, name: response.serverName, token: token)
            refreshTrustedServers()
            persistSelectedServerWithoutRestart(response.serverID)
            sendHello()
            publishState(.connected, detail: "")

        default:
            break
        }
    }

    private func persistSelectedServerWithoutRestart(_ serverID: String) {
        DispatchQueue.main.async {
            self.isPersistingSelectedServerWithoutRestart = true
            self.selectedServerID = serverID
            self.isPersistingSelectedServerWithoutRestart = false
        }
    }

    private func sendHello() {
        guard connection != nil, canvasSize.width > 0, canvasSize.height > 0 else { return }
        sendMessage(
            .hello(
                TabletHello(
                    protocolVersion: inkWandProtocolVersion,
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
            let outgoing: Data
            if let secureSession, message.shouldEncryptOnWire {
                outgoing = try JSONLineCodec.encode(.encrypted(secureSession.encrypt(message)))
            } else {
                outgoing = data
            }
            connection.send(content: outgoing, completion: .contentProcessed { [weak self, weak connection] error in
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

    private static func lowLatencyTCPParameters() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        return NWParameters(tls: nil, tcp: tcpOptions)
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
