import Foundation
#if os(Linux)
import Glibc
#endif

final class ServicePublisher {
    private let process: Process?
    private let lock = NSLock()
    private var didStop = false
    #if os(macOS)
    private let service: NetService?
    private let delegate: NetServiceLogger?
    #endif
    private let verbose: Bool

    #if os(macOS)
    private init(process: Process?, service: NetService? = nil, delegate: NetServiceLogger? = nil, verbose: Bool) {
        self.process = process
        self.service = service
        self.delegate = delegate
        self.verbose = verbose
    }
    #else
    private init(process: Process?, verbose: Bool) {
        self.process = process
        self.verbose = verbose
    }
    #endif

    deinit {
        stop()
    }

    static func startBestEffort(name: String, port: UInt16, verbose: Bool) -> ServicePublisher {
        #if os(macOS)
        let service = NetService(domain: "local.", type: "_inkwand._tcp.", name: name, port: Int32(port))
        let delegate = NetServiceLogger(verbose: verbose)
        service.delegate = delegate
        service.schedule(in: .main, forMode: .common)
        service.publish()
        if verbose {
            print("published Bonjour service _inkwand._tcp on port \(port)")
        }
        return ServicePublisher(process: nil, service: service, delegate: delegate, verbose: verbose)
        #else
        guard let avahiPublishService = commandPath("avahi-publish-service") else {
            print("avahi-publish-service not found; Wi-Fi discovery may not be available.")
            return ServicePublisher(process: nil, verbose: verbose)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: avahiPublishService)
        process.arguments = [name, "_inkwand._tcp", "\(port)"]
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
        #endif
    }

    func stop() {
        lock.lock()
        guard !didStop else {
            lock.unlock()
            return
        }
        didStop = true
        lock.unlock()

        #if os(macOS)
        if let service {
            if verbose {
                print("stopping Bonjour publisher")
            }
            service.stop()
        }
        #endif
        guard let process, process.isRunning else { return }
        if verbose {
            print("stopping Bonjour publisher")
        }
        process.terminate()
        #if os(Linux)
        waitForExit(process, timeout: 2.0)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        #endif
        process.waitUntilExit()
    }

    private static func commandPath(_ name: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }

    #if os(Linux)
    private func waitForExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
    #endif
}

#if os(macOS)
private final class NetServiceLogger: NSObject, NetServiceDelegate {
    private let verbose: Bool

    init(verbose: Bool) {
        self.verbose = verbose
    }

    func netServiceDidPublish(_ sender: NetService) {
        if verbose {
            ServerLog.info("Bonjour service published: \(sender.name).\(sender.type)\(sender.domain)")
        }
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        ServerLog.info("Bonjour service did not publish: \(errorDict)")
    }
}
#endif
