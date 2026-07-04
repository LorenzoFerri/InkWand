#if os(Linux)
import Foundation

enum FirewallAction: String {
    case install
    case uninstall
}

enum FirewallManager {
    static func apply(_ action: FirewallAction, port: UInt16) throws {
        guard Privilege.requireRoot(commandDescription: "Firewall changes") else {
            return
        }

        if commandExists("ufw") {
            try applyUFW(action, port: port)
            return
        }

        if commandExists("firewall-cmd") {
            try applyFirewalld(action, port: port)
            return
        }

        print("No supported firewall tool found.")
        print("Open these ports manually for Wi-Fi mode:")
        print("  TCP \(port)")
        print("  UDP \(port)")
    }

    private static func applyUFW(_ action: FirewallAction, port: UInt16) throws {
        switch action {
        case .install:
            try run("ufw", ["allow", "\(port)/tcp", "comment", "InkWand"])
            try run("ufw", ["allow", "\(port)/udp", "comment", "InkWand"])
            print("Installed ufw rules for InkWand on TCP/UDP \(port).")
        case .uninstall:
            try run("ufw", ["delete", "allow", "\(port)/tcp"])
            try run("ufw", ["delete", "allow", "\(port)/udp"])
            print("Removed ufw rules for InkWand on TCP/UDP \(port).")
        }
    }

    private static func applyFirewalld(_ action: FirewallAction, port: UInt16) throws {
        let operation: String
        switch action {
        case .install:
            operation = "--add-port"
        case .uninstall:
            operation = "--remove-port"
        }

        try run("firewall-cmd", ["--permanent", "\(operation)=\(port)/tcp"])
        try run("firewall-cmd", ["--permanent", "\(operation)=\(port)/udp"])
        try run("firewall-cmd", ["--reload"])

        switch action {
        case .install:
            print("Installed firewalld rules for InkWand on TCP/UDP \(port).")
        case .uninstall:
            print("Removed firewalld rules for InkWand on TCP/UDP \(port).")
        }
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

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServerError.commandFailed(([executable] + arguments).joined(separator: " "), process.terminationStatus)
        }
    }
}
#endif
