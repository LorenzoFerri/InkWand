import Foundation
import InkWandCore
import SwiftCrossUI

struct ServerAppState {
    var runtime: ServerRuntimeSnapshot
    var autostartEnabled: Bool
    var now: Date

    static let initial = ServerAppState(
        runtime: .initial,
        autostartEnabled: false,
        now: Date()
    )

    static func snapshot(
        runtime: InkWandServerRuntime,
        autostartEnabled: Bool,
        now: Date = Date()
    ) -> ServerAppState {
        ServerAppState(
            runtime: ServerRuntimeSnapshot(runtime: runtime),
            autostartEnabled: autostartEnabled,
            now: now
        )
    }
}

struct ServerRuntimeSnapshot {
    var state: InkWandServerRuntime.State
    var serverName: String
    var port: UInt16
    var trustedPeers: [TrustedPeer]
    var pendingPairingRequests: [PendingPairingRequest]
    var activeTabletSession: TabletSessionCoordinator.SessionStatus

    static let initial = ServerRuntimeSnapshot(
        state: .stopped,
        serverName: InkWandServerRuntime.defaultServerName,
        port: 24817,
        trustedPeers: [],
        pendingPairingRequests: [],
        activeTabletSession: .disconnected
    )

    init(
        state: InkWandServerRuntime.State,
        serverName: String,
        port: UInt16,
        trustedPeers: [TrustedPeer],
        pendingPairingRequests: [PendingPairingRequest],
        activeTabletSession: TabletSessionCoordinator.SessionStatus
    ) {
        self.state = state
        self.serverName = serverName
        self.port = port
        self.trustedPeers = trustedPeers
        self.pendingPairingRequests = pendingPairingRequests
        self.activeTabletSession = activeTabletSession
    }

    init(runtime: InkWandServerRuntime) {
        self.init(
            state: runtime.state,
            serverName: runtime.currentServerName,
            port: runtime.currentPort,
            trustedPeers: runtime.trustedPeers,
            pendingPairingRequests: runtime.pendingPairingRequests,
            activeTabletSession: runtime.activeTabletSession
        )
    }

    var statusTitle: String {
        if state == .ready, activeTabletSession.isConnected {
            return "Connected"
        }

        return state.title
    }

    var serverHeadline: String {
        if state == .ready, activeTabletSession.isConnected {
            return "Connected to \(activeTabletSession.deviceName ?? "iPad") via \(activeTabletSession.transport ?? "tablet session")"
        }

        switch state {
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

    var serverDetail: String {
        if state == .ready, activeTabletSession.isConnected {
            return "\(activeTabletSession.deviceName ?? "An iPad") is connected and sending tablet input through \(activeTabletSession.transport ?? "the active transport")."
        }

        switch state {
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

    var statusColor: SwiftCrossUI.Color {
        switch state {
        case .ready:
            return .green
        case .starting:
            return .orange
        case .stopped:
            return .gray
        case .failed:
            return .red
        }
    }
}
