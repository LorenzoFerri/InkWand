#if os(Linux)
import Dispatch
import Foundation
import Glibc

final class UDPDiscoveryResponder: @unchecked Sendable {
    private static let request = "INKWAND_DISCOVER_V1"

    private let port: UInt16
    private let verbose: Bool
    private var fd: Int32 = -1

    init(port: UInt16, verbose: Bool) {
        self.port = port
        self.verbose = verbose
    }

    func start() {
        fd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        guard fd >= 0 else {
            print("UDP discovery unavailable: \(String(cString: strerror(errno)))")
            return
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Glibc.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            print("UDP discovery bind failed: \(String(cString: strerror(errno)))")
            stop()
            return
        }

        if verbose {
            print("UDP discovery ready on 0.0.0.0:\(port).")
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.receiveLoop()
        }
    }

    func stop() {
        if fd >= 0 {
            _ = Glibc.close(fd)
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
                    Glibc.recvfrom(fd, &buffer, buffer.count, 0, sockaddrPointer, &senderLength)
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

            let response = Array("INKWAND_SERVER_V1 \(port)\n".utf8)
            var replyAddress = sender
            _ = withUnsafePointer(to: &replyAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Glibc.sendto(fd, response, response.count, 0, sockaddrPointer, senderLength)
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
#endif
