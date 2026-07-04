#if os(Linux)
import Foundation
import Glibc
import InkWandCore

final class UInputPadDevice {
    private let fd: Int32
    private var isDestroyed = false
    private var isPanning = false

    init() throws {
        let opened = "/dev/uinput".withCString { path in
            Glibc.open(path, O_WRONLY | O_NONBLOCK)
        }

        guard opened >= 0 else {
            throw ServerError.uinputUnavailable(errno)
        }

        fd = opened

        do {
            try configure()
        } catch {
            _ = Glibc.close(fd)
            throw error
        }
    }

    deinit {
        destroy()
    }

    func emit(_ action: PadAction) throws {
        switch action {
        case .undo:
            try tap([LinuxInput.keyLeftCtrl, LinuxInput.keyZ])
        case .redo:
            try tap([LinuxInput.keyLeftCtrl, LinuxInput.keyLeftShift, LinuxInput.keyZ])
        case .brushSmaller:
            try tap([LinuxInput.keyLeftBrace])
        case .brushLarger:
            try tap([LinuxInput.keyRightBrace])
        case .panBegan:
            guard !isPanning else { return }
            isPanning = true
            try key(LinuxInput.keySpace, 1)
            try sync()
        case .panEnded:
            guard isPanning else { return }
            isPanning = false
            try key(LinuxInput.keySpace, 0)
            try sync()
        }
    }

    func release() throws {
        isPanning = false
        try key(LinuxInput.keyLeftCtrl, 0)
        try key(LinuxInput.keyLeftShift, 0)
        try key(LinuxInput.keyZ, 0)
        try key(LinuxInput.keySpace, 0)
        try key(LinuxInput.keyLeftBrace, 0)
        try key(LinuxInput.keyRightBrace, 0)
        try sync()
    }

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true

        try? release()
        _ = linuxIoctl(fd, LinuxInput.uiDevDestroy)
        _ = Glibc.close(fd)
    }

    private func configure() throws {
        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evKey)
        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evSyn)

        for code in Self.supportedKeys {
            try setBit(request: LinuxInput.uiSetKeyBit, value: code)
        }

        if try !configureWithModernUInput() {
            var userDevice = UInputPadUserDeviceBuffer(name: "InkWand Pad")
            userDevice.setInputID(busType: LinuxInput.busUSB, vendor: 0x1209, product: 0x1A0E, version: 1)
            try userDevice.write(to: fd)
        }

        guard linuxIoctl(fd, LinuxInput.uiDevCreate) == 0 else {
            throw ServerError.posix("UI_DEV_CREATE", errno)
        }
    }

    private func configureWithModernUInput() throws -> Bool {
        var setup = UInputPadSetupBuffer(name: "InkWand Pad")
        setup.setInputID(busType: LinuxInput.busUSB, vendor: 0x1209, product: 0x1A0E, version: 1)

        guard linuxIoctlBytes(fd, LinuxInput.uiDevSetup, &setup.bytes) == 0 else {
            if errno == EINVAL {
                return false
            }
            throw ServerError.posix("UI_DEV_SETUP", errno)
        }

        return true
    }

    private func tap(_ keys: [Int32]) throws {
        for code in keys {
            try key(code, 1)
        }
        try sync()

        for code in keys.reversed() {
            try key(code, 0)
        }
        try sync()
    }

    private func key(_ code: Int32, _ value: Int32) throws {
        try writeEvent(type: LinuxInput.evKey, code: code, value: value)
    }

    private func setBit(request: UInt, value: Int32) throws {
        guard linuxIoctl(fd, request, value) == 0 else {
            throw ServerError.posix("ioctl", errno)
        }
    }

    private func writeEvent(type: Int32, code: Int32, value: Int32) throws {
        var event = LinuxInputEvent(type: type, code: code, value: value)
        let written = withUnsafeBytes(of: &event) { bytes in
            Glibc.write(fd, bytes.baseAddress, bytes.count)
        }

        guard written == MemoryLayout<LinuxInputEvent>.size else {
            throw ServerError.posix("write input_event", errno)
        }
    }

    private func sync() throws {
        try writeEvent(type: LinuxInput.evSyn, code: LinuxInput.synReport, value: 0)
    }

    private static let supportedKeys = [
        LinuxInput.keyLeftCtrl,
        LinuxInput.keyLeftShift,
        LinuxInput.keyZ,
        LinuxInput.keySpace,
        LinuxInput.keyLeftBrace,
        LinuxInput.keyRightBrace,
    ]
}

private struct UInputPadSetupBuffer {
    private static let byteCount = 8 + 80 + 4
    private static let nameOffset = 8
    private static let ffEffectsOffset = 88

    var bytes = [UInt8](repeating: 0, count: byteCount)

    init(name: String) {
        let utf8 = Array(name.utf8.prefix(79))
        bytes.replaceSubrange(Self.nameOffset..<(Self.nameOffset + utf8.count), with: utf8)
    }

    mutating func setInputID(busType: UInt16, vendor: UInt16, product: UInt16, version: UInt16) {
        setUInt16(busType, at: 0)
        setUInt16(vendor, at: 2)
        setUInt16(product, at: 4)
        setUInt16(version, at: 6)
        setInt32(0, at: Self.ffEffectsOffset)
    }

    private mutating func setUInt16(_ value: UInt16, at offset: Int) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { raw in
            bytes[offset] = raw[0]
            bytes[offset + 1] = raw[1]
        }
    }

    private mutating func setInt32(_ value: Int32, at offset: Int) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { raw in
            for index in 0..<4 {
                bytes[offset + index] = raw[index]
            }
        }
    }
}

private struct UInputPadUserDeviceBuffer {
    private static let byteCount = 80 + 8 + 4 + (64 * 4 * 4)
    private static let inputIDOffset = 80
    private static let ffEffectsOffset = 88

    private var bytes = [UInt8](repeating: 0, count: byteCount)

    init(name: String) {
        let utf8 = Array(name.utf8.prefix(79))
        bytes.replaceSubrange(0..<utf8.count, with: utf8)
    }

    mutating func setInputID(busType: UInt16, vendor: UInt16, product: UInt16, version: UInt16) {
        setUInt16(busType, at: Self.inputIDOffset)
        setUInt16(vendor, at: Self.inputIDOffset + 2)
        setUInt16(product, at: Self.inputIDOffset + 4)
        setUInt16(version, at: Self.inputIDOffset + 6)
        setInt32(0, at: Self.ffEffectsOffset)
    }

    func write(to fd: Int32) throws {
        let written = bytes.withUnsafeBytes { buffer in
            Glibc.write(fd, buffer.baseAddress, buffer.count)
        }

        guard written == bytes.count else {
            throw ServerError.posix("write uinput_user_dev", errno)
        }
    }

    private mutating func setUInt16(_ value: UInt16, at offset: Int) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { raw in
            bytes[offset] = raw[0]
            bytes[offset + 1] = raw[1]
        }
    }

    private mutating func setInt32(_ value: Int32, at offset: Int) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { raw in
            for index in 0..<4 {
                bytes[offset + index] = raw[index]
            }
        }
    }
}
#endif
