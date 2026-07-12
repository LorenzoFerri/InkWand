import InkWandCore
import SwiftCrossUI

struct StatusSection: View {
    let state: InkWandServerRuntime.State

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppLabel("Status", style: .heading)
                .frame(maxWidth: .infinity, alignment: .leading)
            CardRow {
                HStack(spacing: 13) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 14, height: 14)
                    AppLabel(state.title)
                    Spacer()
                    AppLabel(state.serverHeadline, style: .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var statusColor: SwiftCrossUI.Color {
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

struct ServerInfoSection: View {
    let runtime: InkWandServerRuntime

    var body: some View {
        FormSection("Server") {
            SettingsRow(title: "Computer name", value: runtime.currentServerName)
            Divider()
            SettingsRow(title: "Details", value: runtime.state.serverDetail)
        }
    }
}

struct ConnectionsSection: View {
    let runtime: InkWandServerRuntime
    let refresh: () -> Void

    var body: some View {
        FormSection("Connections") {
            if runtime.pendingPairingRequests.isEmpty {
                EmptyStateRow("No pending pairing requests")
            } else {
                HeaderRow("Pending Pairing Request")
                ForEach(runtime.pendingPairingRequests) { request in
                    PendingPairingRow(
                        request: request,
                        approve: {
                            runtime.approvePairingRequest(id: request.requestID)
                            refresh()
                        },
                        reject: {
                            runtime.rejectPairingRequest(id: request.requestID)
                            refresh()
                        }
                    )
                }
            }
        }
    }
}

private struct PendingPairingRow: View {
    let request: PendingPairingRequest
    let approve: @MainActor @Sendable () -> Void
    let reject: @MainActor @Sendable () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ThemedIcon(.ipad)
            VStack(alignment: .leading, spacing: 3) {
                AppLabel(request.clientName)
                AppLabel(
                    "Expires in \(pairingSecondsRemaining) seconds",
                    style: .caption
                )
            }
            Spacer()
            Button("Accept") {
                approve()
            }
            Button("Reject") {
                reject()
            }
        }
        .padding(12)
    }

    private var pairingSecondsRemaining: Int {
        max(0, Int(request.expiresAt.timeIntervalSinceNow.rounded(.up)))
    }
}

struct TrustedDevicesSection: View {
    let runtime: InkWandServerRuntime
    let refresh: () -> Void

    var body: some View {
        FormSection("Trusted iPads") {
            if runtime.trustedPeers.isEmpty {
                EmptyStateRow("No trusted iPads yet")
            } else {
                ForEach(runtime.trustedPeers) { peer in
                    TrustedDeviceRow(
                        peer: peer,
                        revoke: {
                            runtime.revokePeer(id: peer.peerID)
                            refresh()
                        }
                    )
                }
            }
        }
    }
}

private struct TrustedDeviceRow: View {
    let peer: TrustedPeer
    let revoke: @MainActor @Sendable () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ThemedIcon(.ipad)
            AppLabel(peer.name)
            Spacer()
            AppLabel(peer.lastSeenAt == nil ? "Never connected" : "Last seen recently", style: .secondary)
            Button("Revoke") {
                revoke()
            }
        }
        .padding(12)
    }
}

struct NetworkSection: View {
    let port: Int

    var body: some View {
        FormSection("Network") {
            SettingsRow(title: "USB", value: "Enabled at startup", icon: .usb)
            Divider()
            SettingsRow(title: "Wi-Fi", value: "Enabled at startup", icon: .wifi)
            Divider()
            SettingsRow(title: "Port", value: "\(port)", icon: .port)
        }
    }
}

struct VirtualDevicesSection: View {
    var body: some View {
        FormSection("Virtual Devices") {
            SettingsRow(title: "Pen", value: "Available", icon: .pen)
            Divider()
            SettingsRow(title: "Touch", value: "Available", icon: .touch)
            Divider()
            SettingsRow(title: "Pad", value: "Available", icon: .pad)
        }
    }
}

struct StartupSection: View {
    @Binding var autostartEnabled: Bool
    let setAutostart: (Bool) -> Void
    let openFirewall: @MainActor @Sendable () -> Void

    var body: some View {
        FormSection("Startup") {
            #if os(Linux)
                HStack {
                    AppLabel("Launch at login")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { autostartEnabled },
                        set: { setAutostart($0) }
                    ))
                    .toggleStyle(.switch)
                }
                .padding()
                Divider()
                OpenFirewallRow(openFirewall: openFirewall)
            #else
                HStack {
                    AppLabel("Launch at login")
                    Spacer()
                    AppLabel("Not available on macOS yet", style: .secondary)
                }
                .padding(12)
            #endif
        }
    }
}

private struct OpenFirewallRow: View {
    let openFirewall: @MainActor @Sendable () -> Void

    var body: some View {
        HStack {
            ThemedIcon(.firewall)
            AppLabel("Open Firewall")
            Spacer()
            Button("Open Firewall") {
                openFirewall()
            }
        }
        .padding(12)
    }
}

extension InkWandServerRuntime.State {
    var serverHeadline: String {
        switch self {
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
        switch self {
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
}
