import Foundation

final class USBMuxTunnel {
    private let process: Process
    private let verbose: Bool

    private init(process: Process, verbose: Bool) {
        self.process = process
        self.verbose = verbose
    }

    static func startBestEffort(localPort: UInt16, devicePort: UInt16, verbose: Bool) -> USBMuxTunnel? {
        guard Self.commandExists("iproxy") else {
            print("iproxy not found; using existing tunnel on 127.0.0.1:\(localPort) if available.")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["iproxy", "\(localPort)", "\(devicePort)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("Could not start iproxy: \(error). Using existing tunnel on 127.0.0.1:\(localPort) if available.")
            return nil
        }

        if verbose {
            print("started iproxy \(localPort) \(devicePort)")
        }

        Thread.sleep(forTimeInterval: 0.4)

        if !process.isRunning {
            print("iproxy exited immediately with status \(process.terminationStatus); using existing tunnel on 127.0.0.1:\(localPort) if available.")
            return nil
        }

        return USBMuxTunnel(process: process, verbose: verbose)
    }

    func stop() {
        guard process.isRunning else { return }

        if verbose {
            print("stopping iproxy")
        }

        process.terminate()
        process.waitUntilExit()
    }

    private static func commandExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
