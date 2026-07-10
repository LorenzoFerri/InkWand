import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum NetworkInterfaces {
    static func localIPv4Addresses() -> [String] {
        localIPv4AddressRecords().map { "\($0.address) (\($0.interfaceName))" }
    }

    static func localIPv4AddressRecords() -> [(address: String, interfaceName: String)] {
        var interfacesPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacesPointer) == 0, let firstInterface = interfacesPointer else {
            return []
        }
        defer {
            freeifaddrs(interfacesPointer)
        }

        var addresses: [(address: String, interfaceName: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let interface = current {
            defer {
                current = interface.pointee.ifa_next
            }

            guard let address = interface.pointee.ifa_addr else {
                continue
            }
            guard Int32(address.pointee.sa_family) == AF_INET else {
                continue
            }

            var socketAddress = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let flags = interface.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 else {
                continue
            }

            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &socketAddress.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }

            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let ip = String(decoding: bytes, as: UTF8.self)
            let name = String(cString: interface.pointee.ifa_name)
            addresses.append((address: ip, interfaceName: name))
        }

        return addresses
    }
}
