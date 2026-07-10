#if os(Linux)
import Foundation
import InkWandCore

final class DesktopPairingNotifier: @unchecked Sendable {
    func notify(
        request: PendingPairingRequest,
        approve: @escaping @Sendable () -> Void,
        reject: @escaping @Sendable () -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let stdout = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "notify-send",
                "--app-name=InkWand",
                "--urgency=normal",
                "--expire-time=120000",
                "--wait",
                "--action=accept=Accept",
                "--action=reject=Reject",
                "InkWand iPad request",
                "\(request.clientName) wants to connect to this computer."
            ]
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return }
                let response = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                switch response {
                case "accept":
                    approve()
                case "reject":
                    reject()
                default:
                    break
                }
            } catch {
                ServerLog.info("Desktop pairing notification unavailable: \(error)")
            }
        }
    }
}
#endif
