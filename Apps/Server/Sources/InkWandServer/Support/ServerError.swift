import Foundation
import InkWandCore

enum ServerError: Error, CustomStringConvertible {
    case commandFailed(String, Int32)
    case connectionClosed
    case invalidHost(String)
    case portInUse(UInt16)
    case posix(String, Int32)
    case unsupportedProtocolVersion(Int)
    case uinputUnavailable(Int32)

    var description: String {
        switch self {
        case let .commandFailed(command, status):
            return "Command failed with status \(status): \(command)"
        case .connectionClosed:
            return "Connection closed by the iPad."
        case let .invalidHost(host):
            return "Invalid host: \(host)."
        case let .portInUse(port):
            return "Port \(port) is already in use. Stop the process using that port, or run InkWandServer --port <other-port>."
        case let .posix(operation, code):
            return "\(operation) failed: \(String(cString: strerror(code)))"
        case let .unsupportedProtocolVersion(version):
            return "Unsupported InkWand protocol version \(version); expected \(inkWandProtocolVersion)."
        case let .uinputUnavailable(code):
            return "Could not open /dev/uinput: \(String(cString: strerror(code))). Check Linux uinput permissions, group membership, or udev rules."
        }
    }
}
