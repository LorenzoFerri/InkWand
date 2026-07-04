#if os(Linux)
import Foundation
import Glibc

enum Privilege {
    static var isRoot: Bool {
        geteuid() == 0
    }

    static func requireRoot(commandDescription: String) -> Bool {
        guard !isRoot else { return true }

        let executable = CommandLine.arguments.first ?? "InkWandServer"
        let arguments = CommandLine.arguments.dropFirst().joined(separator: " ")
        print("\(commandDescription) requires administrator privileges.")
        print("Run this command instead:")
        print("  sudo \(executable) \(arguments)")
        return false
    }
}
#endif
