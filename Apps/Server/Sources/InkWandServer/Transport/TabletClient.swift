import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import InkWandCore

final class TabletClient: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let verbose: Bool
    private var fd: Int32 = -1
    var secureSession: SecureSession?

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

        #if os(Linux)
        fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
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
                #if os(Linux)
                Glibc.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                #else
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                #endif
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
            #if os(Linux)
            let readCount = Glibc.recv(fd, &buffer, buffer.count, 0)
            #else
            let readCount = Darwin.recv(fd, &buffer, buffer.count, 0)
            #endif
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
                    let decoded = try JSONLineCodec.decodeLine(Data(line))
                    if case let .encrypted(envelope) = decoded {
                        guard let secureSession else {
                            throw SecureChannelError.authenticationFailed
                        }
                        try handle(try secureSession.decrypt(envelope))
                    } else {
                        try handle(decoded)
                    }
                } catch let error as DecodingError {
                    print("warning: malformed JSON message ignored: \(error)")
                }
            }
        }
    }

    func sendMessage(_ message: InkMessage) throws {
        try sendMessage(message, encrypted: true)
    }

    func sendMessage(_ message: InkMessage, encrypted: Bool) throws {
        let outgoing: InkMessage
        if encrypted, let secureSession, message.shouldEncryptOnWire {
            outgoing = try .encrypted(secureSession.encrypt(message))
        } else {
            outgoing = message
        }
        let data = try JSONLineCodec.encode(outgoing)
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                #if os(Linux)
                let written = Glibc.send(fd, baseAddress.advanced(by: sent), data.count - sent, 0)
                #else
                let written = Darwin.send(fd, baseAddress.advanced(by: sent), data.count - sent, 0)
                #endif
                guard written > 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw ServerError.posix("send", errno)
                }
                sent += written
            }
        }
    }

    func close() {
        if fd >= 0 {
            #if os(Linux)
            _ = Glibc.close(fd)
            #else
            _ = Darwin.close(fd)
            #endif
            fd = -1
        }
    }

    private static func setLowLatency(_ fd: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }
}
