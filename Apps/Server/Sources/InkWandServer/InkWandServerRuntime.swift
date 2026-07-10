#if os(Linux)
import Dispatch
import Foundation
import InkWandCore

final class InkWandServerRuntime: @unchecked Sendable {
    enum State: Equatable {
        case stopped
        case starting
        case ready
        case failed(String)

        var title: String {
            switch self {
            case .stopped:
                return "Not running"
            case .starting:
                return "Starting..."
            case .ready:
                return "Ready"
            case .failed:
                return "Needs attention"
            }
        }
    }

    private let lock = NSLock()
    private var port: UInt16
    private var serverName: String
    private var verbose: Bool
    private var enableUSB: Bool
    private var enableWiFi: Bool
    private var isRunning = false
    private var pairingCode: ActivePairingCode?
    private var trustStore: TrustStore?
    private var pairingManager: PairingManager?
    private var authenticator: TabletSessionAuthenticator?
    private var coordinator: TabletSessionCoordinator?
    private var wifiListener: WiFiTabletListener?
    private var udpDiscovery: UDPDiscoveryResponder?
    private var publisher: ServicePublisher?
    private var tunnel: USBMuxTunnel?
    private var pairingTimer: DispatchSourceTimer?
    private let pairingNotifier = DesktopPairingNotifier()
    private var notifiedPairingRequestIDs = Set<String>()

    var onChange: (() -> Void)?

    private(set) var state: State = .stopped {
        didSet { notifyChanged() }
    }

    init(port: UInt16 = 24817, serverName: String = "InkWand", verbose: Bool = false, enableUSB: Bool = true, enableWiFi: Bool = true) {
        self.port = port
        self.serverName = serverName
        self.verbose = verbose
        self.enableUSB = enableUSB
        self.enableWiFi = enableWiFi
    }

    var currentPort: UInt16 { lock.withLock { port } }
    var currentServerName: String { lock.withLock { trustStore?.localName ?? serverName } }
    var serverID: String { lock.withLock { trustStore?.localID ?? "" } }
    var currentPairingCode: ActivePairingCode? { lock.withLock { pairingCode } }
    var trustedPeers: [TrustedPeer] { lock.withLock { trustStore?.allPeers() ?? [] } }
    var pendingPairingRequests: [PendingPairingRequest] { lock.withLock { pairingManager?.pendingApprovals() ?? [] } }

    func start(pairing: Bool = false) throws {
        lock.lock()
        if isRunning {
            lock.unlock()
            if pairing {
                _ = beginPairing()
            }
            return
        }
        state = .starting
        lock.unlock()

        do {
            guard port < UInt16.max else {
                throw ValidationFailure("--port must be lower than 65535 because InkWand uses the next local port for USB tunneling.")
            }
            guard enableUSB || enableWiFi else {
                throw ValidationFailure("At least one transport must be enabled.")
            }

            let paths = ProductPaths.default
            let store = try TrustStore(url: paths.trustStoreURL, defaultLocalName: serverName)
            store.localName = serverName
            let manager = PairingManager(store: store)
            let sessionAuthenticator = TabletSessionAuthenticator(pairingManager: manager, trustStore: store)
            sessionAuthenticator.onPairingRequestsChanged = { [weak self] in
                self?.publishNotificationsForNewPairingRequests()
                self?.notifyChanged()
            }
            let bindingStore = try PadBindingStore(url: paths.bindingStoreURL)
            let mapper = TabletMapper()
            let device = try UInputPenDevice(maxX: mapper.maxX, maxY: mapper.maxY, maxPressure: mapper.maxPressure)
            let touchDevice = try UInputTouchDevice(maxX: mapper.maxX, maxY: mapper.maxY)
            let padDevice = try UInputPadDevice(bindingMap: try bindingStore.load().validating(allowedKeyCodes: LinuxInput.keyEsc...LinuxInput.keyMicMute))
            let sessionCoordinator = TabletSessionCoordinator(
                device: device,
                padDevice: padDevice,
                touchDevice: touchDevice,
                authenticator: sessionAuthenticator,
                verbose: verbose
            )

            let advertisedPort = port
            let listener = enableWiFi ? WiFiTabletListener(port: port, verbose: verbose, coordinator: sessionCoordinator) : nil
            let discovery = enableWiFi ? UDPDiscoveryResponder(
                advertisementProvider: {
                    ServerAdvertisement(
                        serverID: sessionAuthenticator.serverID,
                        name: sessionAuthenticator.serverName,
                        port: advertisedPort,
                        pairingAvailable: sessionAuthenticator.pairingAvailable
                    )
                },
                verbose: verbose
            ) : nil

            try listener?.start()
            discovery?.start()
            let usbLocalPort = port + 1
            let activeTunnel = enableUSB ? USBMuxTunnel.startBestEffort(localPort: usbLocalPort, devicePort: port, verbose: verbose) : nil
            let activePublisher = enableWiFi ? ServicePublisher.startBestEffort(name: serverName, port: port, verbose: verbose) : nil

            lock.lock()
            isRunning = true
            trustStore = store
            pairingManager = manager
            authenticator = sessionAuthenticator
            coordinator = sessionCoordinator
            wifiListener = listener
            udpDiscovery = discovery
            tunnel = activeTunnel
            publisher = activePublisher
            state = .ready
            lock.unlock()

            if enableUSB {
                startUSBConnectorLoop(port: usbLocalPort, coordinator: sessionCoordinator)
            }

            if pairing {
                _ = beginPairing()
            }
        } catch {
            lock.lock()
            isRunning = false
            state = .failed(userFacingError(error))
            lock.unlock()
            throw error
        }
    }

    func stop() {
        lock.lock()
        isRunning = false
        pairingTimer?.cancel()
        pairingTimer = nil
        pairingCode = nil
        let activeCoordinator = coordinator
        let activeListener = wifiListener
        let activeDiscovery = udpDiscovery
        let activePublisher = publisher
        let activeTunnel = tunnel
        coordinator = nil
        wifiListener = nil
        udpDiscovery = nil
        publisher = nil
        tunnel = nil
        state = .stopped
        lock.unlock()

        activeCoordinator?.releaseAndDestroy()
        activeListener?.stop()
        activeDiscovery?.stop()
        activePublisher?.stop()
        activeTunnel?.stop()
    }

    @discardableResult
    func beginPairing() -> ActivePairingCode? {
        lock.lock()
        guard let manager = pairingManager else {
            lock.unlock()
            return nil
        }
        let code = manager.beginPairing()
        pairingCode = code
        pairingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        pairingTimer = timer
        lock.unlock()

        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.refreshPairingCode()
        }
        timer.resume()
        notifyChanged()
        return code
    }

    func cancelPairing() {
        lock.lock()
        pairingManager?.cancelPairing()
        pairingTimer?.cancel()
        pairingTimer = nil
        pairingCode = nil
        lock.unlock()
        notifyChanged()
    }

    func revokePeer(id: String) {
        lock.lock()
        do {
            try trustStore?.revoke(peerID: id)
        } catch {
            ServerLog.info("Failed to revoke trusted peer \(id): \(error)")
        }
        lock.unlock()
        notifyChanged()
    }

    func approvePairingRequest(id: String) {
        lock.lock()
        do {
            try pairingManager?.approvePendingSecure(requestID: id)
            notifiedPairingRequestIDs.remove(id)
        } catch {
            ServerLog.info("Failed to approve pairing request \(id): \(error)")
        }
        lock.unlock()
        notifyChanged()
    }

    func rejectPairingRequest(id: String) {
        lock.lock()
        do {
            try pairingManager?.rejectPending(requestID: id)
            notifiedPairingRequestIDs.remove(id)
        } catch {
            ServerLog.info("Failed to reject pairing request \(id): \(error)")
        }
        lock.unlock()
        notifyChanged()
    }

    private func refreshPairingCode() {
        lock.lock()
        if let pairingCode, pairingCode.expiresAt <= Date() {
            self.pairingCode = nil
            pairingTimer?.cancel()
            pairingTimer = nil
        }
        lock.unlock()
        notifyChanged()
    }

    private func publishNotificationsForNewPairingRequests() {
        let requests = pendingPairingRequests
        let pendingIDs = Set(requests.map(\.requestID))

        lock.lock()
        notifiedPairingRequestIDs = notifiedPairingRequestIDs.intersection(pendingIDs)
        let newRequests = requests.filter { notifiedPairingRequestIDs.insert($0.requestID).inserted }
        lock.unlock()

        newRequests.forEach { request in
            pairingNotifier.notify(
                request: request,
                approve: { [weak self] in self?.approvePairingRequest(id: request.requestID) },
                reject: { [weak self] in self?.rejectPairingRequest(id: request.requestID) }
            )
        }
    }

    private func startUSBConnectorLoop(port: UInt16, coordinator: TabletSessionCoordinator) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak coordinator] in
            var lastWaitingMessage = Date.distantPast
            var retryDelay = 2.0
            let maxRetryDelay = 30.0

            while self?.isRuntimeRunning == true {
                guard let coordinator else { return }
                let client = TabletClient(host: "127.0.0.1", port: port, verbose: false)

                do {
                    try client.connect()
                    let activated = coordinator.runSession(client, transport: "USB")
                    retryDelay = activated ? 2.0 : min(retryDelay * 1.8, maxRetryDelay)
                } catch {
                    let now = Date()
                    if now.timeIntervalSince(lastWaitingMessage) >= 5 {
                        ServerLog.info("Waiting for USB InkWand connection on 127.0.0.1:\(port)...")
                        if self?.verbose == true {
                            ServerLog.info("last USB state: \(error)")
                        }
                        lastWaitingMessage = now
                    }
                    retryDelay = min(retryDelay * 1.8, maxRetryDelay)
                }

                Thread.sleep(forTimeInterval: retryDelay)
            }
        }
    }

    private var isRuntimeRunning: Bool {
        lock.withLock { isRunning }
    }

    private func notifyChanged() {
        DispatchQueue.main.async { [onChange] in
            onChange?()
        }
    }

    private func userFacingError(_ error: Error) -> String {
        let text = String(describing: error)
        if text.contains("uinput") || text.contains("/dev/uinput") {
            return "InkWand cannot access /dev/uinput. Run the one-time input permission setup, then reopen the app."
        }
        return text
    }
}

private struct ValidationFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
#endif
