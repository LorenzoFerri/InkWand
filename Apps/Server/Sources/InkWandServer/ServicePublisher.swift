import Foundation

final class ServicePublisher {
    private let process: Process?
    private let verbose: Bool

    private init(process: Process?, verbose: Bool) {
        self.process = process
        self.verbose = verbose
    }

    static func startBestEffort(name: String, port: UInt16, verbose: Bool) -> ServicePublisher {
        guard commandExists("avahi-publish-service") else {
            print("avahi-publish-service not found; Wi-Fi discovery may not be available.")
            return ServicePublisher(process: nil, verbose: verbose)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["avahi-publish-service", name, "_inkwand._tcp", "\(port)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            Thread.sleep(forTimeInterval: 0.3)
            guard process.isRunning else {
                print("avahi-publish-service exited immediately; Wi-Fi discovery may not be available.")
                return ServicePublisher(process: nil, verbose: verbose)
            }

            if verbose {
                print("published Bonjour service _inkwand._tcp on port \(port)")
            }
            return ServicePublisher(process: process, verbose: verbose)
        } catch {
            print("Could not publish Bonjour service: \(error)")
            return ServicePublisher(process: nil, verbose: verbose)
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        if verbose {
            print("stopping Bonjour publisher")
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
