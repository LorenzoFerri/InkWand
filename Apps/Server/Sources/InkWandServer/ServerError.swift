import Foundation

enum ServerError: Error, CustomStringConvertible {
    case commandFailed(String, Int32)
    case connectionClosed
    case invalidHost(String)
    case coreHIDUnavailable
    case portInUse(UInt16)
    case posix(String, Int32)
    case uinputUnavailable(Int32)

    var description: String {
        switch self {
        case let .commandFailed(command, status):
            return "Command failed with status \(status): \(command)"
        case .connectionClosed:
            return "Connection closed by the iPad."
        case let .invalidHost(host):
            return "Invalid host: \(host)."
        case .coreHIDUnavailable:
            return "Could not create the macOS virtual HID tablet device. Check that InkWand has the required input permissions, then reopen the app."
        case let .portInUse(port):
            return "Port \(port) is already in use. Stop the process using that port, or run InkWandServer --port <other-port>."
        case let .posix(operation, code):
            return "\(operation) failed: \(String(cString: strerror(code)))"
        case let .uinputUnavailable(code):
            return "Could not open /dev/uinput: \(String(cString: strerror(code))). Check Linux uinput permissions, group membership, or udev rules."
        }
    }
}
