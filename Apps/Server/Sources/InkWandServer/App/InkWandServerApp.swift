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

    @State private var appState = ServerAppState.initial
    @State private var pairingCountdownTimer: DispatchSourceTimer?

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
        appState = ServerAppState.snapshot(
            runtime: Self.runtime,
            autostartEnabled: appState.autostartEnabled
        )
    }

    var body: some Scene {
        Window("InkWand Server", id: "settings") {
            #hotReloadable {
                ServerSettingsView(
                    runtime: Self.runtime,
                    appState: appState,
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

        StatusItem("InkWand", id: "inkwand-server", tooltip: "InkWand Server: \(appState.runtime.statusTitle)") {
            Text("InkWand Server")
            Text(appState.runtime.serverHeadline)
            if appState.runtime.pendingPairingRequests.isEmpty {
                Text("No pending iPad requests")
            } else {
                Text("\(appState.runtime.pendingPairingRequests.count) iPad request pending")
                ForEach(appState.runtime.pendingPairingRequests) { request in
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
                Button(appState.autostartEnabled ? "Disable launch at startup" : "Launch when system starts") {
                    setAutostart(enabled: !appState.autostartEnabled)
                }
                Divider()
            #endif
            Button("Quit") {
                stopPairingCountdownTimer()
                Self.runtime.stop()
                Foundation.exit(0)
            }
        } primaryAction: {
            openWindow(id: "settings")
        }
    }

    private func refresh() {
        appState = ServerAppState.snapshot(
            runtime: Self.runtime,
            autostartEnabled: appState.autostartEnabled
        )
        syncPairingCountdownTimer()
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
            appState = ServerAppState.snapshot(
                runtime: Self.runtime,
                autostartEnabled: enabled
            )
            syncPairingCountdownTimer()
        } catch {
            ServerLog.info("Autostart failed: \(error)")
            refresh()
        }
    }

    private func syncPairingCountdownTimer() {
        guard !appState.runtime.pendingPairingRequests.isEmpty else {
            stopPairingCountdownTimer()
            return
        }

        guard pairingCountdownTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler {
            tickPairingCountdownClock()
        }
        pairingCountdownTimer = timer
        timer.resume()
    }

    private func stopPairingCountdownTimer() {
        pairingCountdownTimer?.cancel()
        pairingCountdownTimer = nil
    }

    private func tickPairingCountdownClock() {
        let now = Date()
        appState.now = now

        if appState.runtime.pendingPairingRequests.contains(where: { $0.expiresAt <= now }) {
            refresh()
            return
        }

        syncPairingCountdownTimer()
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
