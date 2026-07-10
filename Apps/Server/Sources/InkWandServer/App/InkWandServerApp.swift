import Foundation
import InkWandCore
import DefaultBackend
import SwiftCrossUI

@main
struct InkWandServerApp: App {
    private static let runtime = InkWandServerRuntime()
    @State private var refreshID = 0
    @State private var autostartEnabled = false

    @Environment(\.openWindow) var openWindow

    init() {
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
