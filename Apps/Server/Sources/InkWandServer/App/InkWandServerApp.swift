import DefaultBackend
import Foundation
import InkWandCore
import SwiftCrossUI

#if canImport(SwiftBundlerRuntime)
    import SwiftBundlerRuntime
#endif

@main
@HotReloadable
struct InkWandServerApp: App {
    private static let runtime = InkWandServerRuntime()
    private static let shutdownCoordinator = ShutdownCoordinator()

    @State private var refreshID = 0
    @State private var autostartEnabled = false

    @Environment(\.openWindow) var openWindow

    init() {
        GTKThemePreference.configureIfPossible()
        Self.shutdownCoordinator.setCleanup {
            Self.runtime.stop()
        }
        Self.shutdownCoordinator.installSignalHandlers()

        do {
            try Self.runtime.start()
        } catch {
            ServerLog.info("Failed to start InkWand Server: \(error)")
        }
    }

    var body: some Scene {
        Window("InkWand Server", id: "settings") {
            #hotReloadable {
                ServerSettingsView(
                    runtime: Self.runtime,
                    autostartEnabled: $autostartEnabled,
                    refresh: refresh,
                    setAutostart: setAutostart,
                    openFirewall: openFirewall
                )
                .onAppear {
                    Self.runtime.onChange = {
                        refresh()
                    }
                    refresh()
                }
            }
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 980, height: 660)

        StatusItem("InkWand", id: "inkwand-server", tooltip: "InkWand Server: \(Self.runtime.state.title)") {
            Text("InkWand Server")
            Text(Self.runtime.state.serverHeadline)
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

    private func openFirewall() {
        #if os(Linux)
            let candidates = [
                ["firewall-config"],
                ["xdg-open", "settings://network/firewall"],
            ]
            for command in candidates {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = command
                if (try? process.run()) != nil {
                    return
                }
            }
        #endif
    }
}
