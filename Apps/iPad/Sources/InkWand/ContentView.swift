#if canImport(SwiftUI)
import InkWandCore
import SwiftUI

struct ContentView: View {
    @StateObject private var connection = TabletConnection()
    @State private var showsControls = true
    @State private var controlsPosition: ControlsPosition = .top

    private let minimumControlsHeight: CGFloat = 82
    private let drawingOuterPadding: CGFloat = 16
    private let drawingAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let drawingHeight = drawingSurfaceHeight(in: proxy.size)
                let controlsHeight = max(proxy.size.height - drawingHeight, minimumControlsHeight)

                VStack(spacing: 0) {
                    if controlsPosition == .top {
                        controlsContent
                            .frame(height: controlsHeight)
                            .zIndex(1)
                        drawingSurface
                            .frame(height: drawingHeight)
                            .zIndex(0)
                    } else {
                        drawingSurface
                            .frame(height: drawingHeight)
                            .zIndex(0)
                        controlsContent
                            .frame(height: controlsHeight)
                            .zIndex(1)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }

            if connection.state != .connected {
                GuidedConnectionView(connection: connection)
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .bottom)
        .persistentSystemOverlays(.hidden)
    }

    private var controlsContent: some View {
        ControlDeckView(
            connection: connection,
            showsControls: $showsControls,
            controlsPosition: $controlsPosition
        )
        .padding(.horizontal, 16)
    }

    private var drawingSurface: some View {
        PencilCaptureRepresentable(
            connection: connection,
            controlsPosition: controlsPosition,
            reservesControlDeckSpace: false
        )
        .background(Color.black)
        .frame(maxWidth: .infinity)
    }

    private func drawingSurfaceHeight(in size: CGSize) -> CGFloat {
        let activeWidth = max(size.width - drawingOuterPadding * 2, 0)
        let idealHeight = activeWidth / drawingAspectRatio + drawingOuterPadding * 2
        let maximumHeight = max(size.height - minimumControlsHeight, 0)
        return min(idealHeight, maximumHeight)
    }
}

private struct GuidedConnectionView: View {
    @ObservedObject var connection: TabletConnection

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
            }

            serverList

            if !connection.detail.isEmpty {
                Text(connection.detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Retry") {
                    connection.retrySelectedServer()
                }
                .buttonStyle(.bordered)

                if connection.selectedServerID != nil {
                    Button("Choose another computer") {
                        connection.forgetSelectedServer()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .padding(24)
        .frame(maxWidth: 620)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var title: String {
        switch connection.state {
        case .waiting:
            return "Open InkWand on your computer"
        case .searching:
            return "Choose your computer"
        case .connecting:
            return "Connecting..."
        case .pairing:
            return "Approve on your computer"
        case .authenticating:
            return "Checking this computer..."
        case .connected:
            return "Ready to draw"
        case .failed:
            return "Needs attention"
        }
    }

    private var subtitle: String {
        if connection.state == .pairing {
            return "InkWand Server is showing a request. Accept it on your computer to authorize this iPad."
        }
        if connection.discoveredServers.isEmpty {
            return "Make sure your iPad and computer are on the same Wi-Fi network, then keep InkWand Server open."
        }
        return "Tap the computer you want to use with this iPad."
    }

    private var serverList: some View {
        VStack(spacing: 10) {
            if connection.discoveredServers.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for InkWand Server...")
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(connection.discoveredServers) { server in
                    Button {
                        connection.connectToServer(server)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(serverStatus(server))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(14)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func serverStatus(_ server: ServerAdvertisement) -> String {
        if connection.isTrusted(server) {
            return "Already authorized"
        }
        return "Tap to request access"
    }
}

#endif
