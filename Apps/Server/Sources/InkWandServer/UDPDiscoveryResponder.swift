import Dispatch
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import InkWandCore

final class UDPDiscoveryResponder: @unchecked Sendable {
    private static let request = "INKWAND_DISCOVER_V1"

    private let advertisementProvider: @Sendable () -> ServerAdvertisement
    private let verbose: Bool
    private var fd: Int32 = -1

    init(
        advertisementProvider: @escaping @Sendable () -> ServerAdvertisement,
        verbose: Bool
    ) {
        self.advertisementProvider = advertisementProvider
        self.verbose = verbose
    }

    func start() {
        #if os(Linux)
        fd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        #else
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        #endif
        guard fd >= 0 else {
            print("UDP discovery unavailable: \(String(cString: strerror(errno)))")
            return
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = advertisementProvider().port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                #if os(Linux)
                Glibc.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                #else
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                #endif
            }
        }

        guard bindResult == 0 else {
            print("UDP discovery bind failed: \(String(cString: strerror(errno)))")
            stop()
            return
        }

        if verbose {
            print("UDP discovery ready on 0.0.0.0:\(advertisementProvider().port).")
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.receiveLoop()
        }
    }

    func stop() {
        if fd >= 0 {
            #if os(Linux)
            _ = Glibc.close(fd)
            #else
            _ = Darwin.close(fd)
            #endif
            fd = -1
        }
    }

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 512)

        while fd >= 0 {
            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    #if os(Linux)
                    Glibc.recvfrom(fd, &buffer, buffer.count, 0, sockaddrPointer, &senderLength)
                    #else
                    Darwin.recvfrom(fd, &buffer, buffer.count, 0, sockaddrPointer, &senderLength)
                    #endif
                }
            }

            guard count > 0 else {
                if errno == EINTR {
                    continue
                }
                if verbose, fd >= 0 {
                    print("UDP discovery receive failed: \(String(cString: strerror(errno)))")
                }
                Thread.sleep(forTimeInterval: 1.0)
                continue
            }

            let request = String(decoding: buffer.prefix(Int(count)), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard request == Self.request else {
                continue
            }

            let advertisement = advertisementProvider()
            let response: [UInt8]
            if let data = try? JSONEncoder().encode(advertisement), let body = String(data: data, encoding: .utf8) {
                response = Array("INKWAND_SERVER_V2 \(body)\n".utf8)
            } else {
                response = Array("INKWAND_SERVER_V1 \(advertisement.port)\n".utf8)
            }
            var replyAddress = sender
            _ = withUnsafePointer(to: &replyAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    #if os(Linux)
                    Glibc.sendto(fd, response, response.count, 0, sockaddrPointer, senderLength)
                    #else
                    Darwin.sendto(fd, response, response.count, 0, sockaddrPointer, senderLength)
                    #endif
                }
            }

            if verbose {
                var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &sender.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                let ipBytes = ipBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                print("Answered UDP discovery from \(String(decoding: ipBytes, as: UTF8.self)).")
            }
        }
    }
}
