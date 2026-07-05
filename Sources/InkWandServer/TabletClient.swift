#if os(Linux)
import Foundation
import Glibc
import InkWandCore

final class TabletClient: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let verbose: Bool
    private var fd: Int32 = -1

    init(host: String, port: UInt16, verbose: Bool) {
        self.host = host
        self.port = port
        self.verbose = verbose
    }

    init(acceptedFileDescriptor: Int32, verbose: Bool) {
        self.host = "accepted"
        self.port = 0
        self.verbose = verbose
        self.fd = acceptedFileDescriptor
        Self.setLowLatency(fd)
    }

    deinit {
        close()
    }

    func connect() throws {
        guard fd < 0 else {
            return
        }

        fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else {
            throw ServerError.posix("socket", errno)
        }
        Self.setLowLatency(fd)

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian

        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw ServerError.invalidHost(host)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Glibc.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard result == 0 else {
            throw ServerError.posix("connect", errno)
        }

        if verbose {
            print("connected to \(host):\(port)")
        }
    }

    func readMessages(_ handle: (InkMessage) throws -> Void) throws {
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let readCount = Glibc.recv(fd, &buffer, buffer.count, 0)
            if readCount == 0 {
                throw ServerError.connectionClosed
            }
            guard readCount > 0 else {
                if errno == EINTR {
                    continue
                }
                throw ServerError.posix("recv", errno)
            }

            pending.append(buffer, count: readCount)

            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending.prefix(through: newline)
                pending.removeSubrange(...newline)

                do {
                    try handle(try JSONLineCodec.decodeLine(Data(line)))
                } catch let error as DecodingError {
                    print("warning: malformed JSON message ignored: \(error)")
                }
            }
        }
    }

    func close() {
        if fd >= 0 {
            _ = Glibc.close(fd)
            fd = -1
        }
    }

    private static func setLowLatency(_ fd: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }
}
#endif
