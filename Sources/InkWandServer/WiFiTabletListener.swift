#if os(Linux)
import Dispatch
import Foundation
import Glibc

final class WiFiTabletListener: @unchecked Sendable {
    private let port: UInt16
    private let verbose: Bool
    private let coordinator: TabletSessionCoordinator
    private var listenFD: Int32 = -1

    init(port: UInt16, verbose: Bool, coordinator: TabletSessionCoordinator) {
        self.port = port
        self.verbose = verbose
        self.coordinator = coordinator
    }

    func start() throws {
        listenFD = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard listenFD >= 0 else {
            throw ServerError.posix("wifi socket", errno)
        }

        var yes: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Glibc.bind(listenFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            stop()
            if code == EADDRINUSE {
                throw ServerError.portInUse(port)
            }
            throw ServerError.posix("wifi bind", code)
        }

        guard Glibc.listen(listenFD, 4) == 0 else {
            let code = errno
            stop()
            throw ServerError.posix("wifi listen", code)
        }

        print("Wi-Fi listener ready on 0.0.0.0:\(port).")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        if listenFD >= 0 {
            _ = Glibc.close(listenFD)
            listenFD = -1
        }
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            var address = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let acceptedFD = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Glibc.accept(listenFD, sockaddrPointer, &length)
                }
            }

            guard acceptedFD >= 0 else {
                if errno == EINTR {
                    continue
                }
                if verbose {
                    print("wifi accept failed: \(String(cString: strerror(errno)))")
                }
                Thread.sleep(forTimeInterval: 1.0)
                continue
            }

            if verbose {
                var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var acceptedAddress = address.sin_addr
                inet_ntop(AF_INET, &acceptedAddress, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                let ipBytes = ipBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                print("Accepted Wi-Fi TCP connection from \(String(decoding: ipBytes, as: UTF8.self)).")
            }

            let client = TabletClient(acceptedFileDescriptor: acceptedFD, verbose: verbose)
            DispatchQueue.global(qos: .userInitiated).async { [coordinator] in
                coordinator.runSession(client, transport: "Wi-Fi")
            }
        }
    }
}
#endif
