#if os(Linux)
import Foundation
import Glibc
import InkWandCore

final class UInputPenDevice {
    private let fd: Int32
    private let maxX: Int32
    private let maxY: Int32
    private let maxPressure: Int32
    private var isDestroyed = false
    private var activeTool: PencilTool?
    private var isTouching = false
    private var lastEventDate = Date.distantPast
    private let toolSwitchSettleMicroseconds: useconds_t = 10_000

    init(maxX: Int32, maxY: Int32, maxPressure: Int32) throws {
        self.maxX = maxX
        self.maxY = maxY
        self.maxPressure = maxPressure

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

    func emitDownOrMove(_ event: MappedPenEvent) throws {
        lastEventDate = Date()

        if let activeTool, activeTool != event.tool {
            try switchTool(to: event.tool, timestamp: event.timestamp)
        } else if activeTool == nil {
            try setActiveTool(event.tool)
        }

        if !isTouching {
            try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnTouch, value: 1)
            isTouching = true
        }

        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absX, value: event.x)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absY, value: event.y)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absPressure, value: event.pressure)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absDistance, value: 0)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absTiltX, value: event.tiltX)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absTiltY, value: event.tiltY)
        try writeEvent(type: LinuxInput.evMsc, code: LinuxInput.mscTimestamp, value: Self.timestampValue(event.timestamp))
        try sync()
    }

    @discardableResult
    func release(timestamp: UInt64 = 0) throws -> Bool {
        guard hasActiveState else { return false }

        try emitToolOut(timestamp: timestamp)
        return true
    }

    func switchTool(to tool: PencilTool, timestamp: UInt64 = 0) throws {
        guard activeTool != tool else {
            try liftTouch(tool: tool, timestamp: timestamp)
            return
        }

        if hasActiveState {
            try emitToolOut(timestamp: timestamp)
            usleep(toolSwitchSettleMicroseconds)
        }

        try liftTouch(tool: tool, timestamp: timestamp)
    }

    private func emitToolOut(timestamp: UInt64) throws {
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnTouch, value: 0)
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolPen, value: 0)
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolRubber, value: 0)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absPressure, value: 0)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absDistance, value: 1)
        try writeEvent(type: LinuxInput.evMsc, code: LinuxInput.mscTimestamp, value: Self.timestampValue(timestamp))
        try sync()
        activeTool = nil
        isTouching = false
        lastEventDate = Date()
    }

    func releaseIfStale(minimumAge: TimeInterval, timestamp: UInt64 = 0) throws -> Bool {
        guard hasActiveState, Date().timeIntervalSince(lastEventDate) >= minimumAge else {
            return false
        }

        return try release(timestamp: timestamp)
    }

    func releaseHover(timestamp: UInt64 = 0) throws -> Bool {
        guard activeTool != nil, !isTouching else { return false }
        return try release(timestamp: timestamp)
    }

    func liftTouch(tool: PencilTool = .pen, timestamp: UInt64 = 0) throws {
        try setActiveTool(tool)
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnTouch, value: 0)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absPressure, value: 0)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absDistance, value: 0)
        try writeEvent(type: LinuxInput.evMsc, code: LinuxInput.mscTimestamp, value: Self.timestampValue(timestamp))
        try sync()
        activeTool = tool
        isTouching = false
        lastEventDate = Date()
    }

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true

        _ = try? release()
        _ = linuxIoctl(fd, LinuxInput.uiDevDestroy)
        _ = Glibc.close(fd)
    }

    private func configure() throws {
        try setString(request: LinuxInput.uiSetPhys, value: "inkwand/pen")

        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evKey)
        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evAbs)
        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evMsc)
        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evSyn)
        _ = linuxIoctl(fd, LinuxInput.uiSetPropBit, LinuxInput.inputPropDirect)

        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnToolPen)
        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnToolRubber)
        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnTouch)

        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absX)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absY)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absPressure)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absDistance)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absTiltX)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absTiltY)
        try setBit(request: LinuxInput.uiSetMscBit, value: LinuxInput.mscTimestamp)

        if try !configureWithModernUInput() {
            var userDevice = UInputUserDeviceBuffer(name: Self.deviceName)
            userDevice.setInputID(busType: LinuxInput.busVirtual, vendor: 0x1701, product: 0x1701, version: 1)
            userDevice.setAbsoluteAxis(code: LinuxInput.absX, minimum: 0, maximum: maxX)
            userDevice.setAbsoluteAxis(code: LinuxInput.absY, minimum: 0, maximum: maxY)
            userDevice.setAbsoluteAxis(code: LinuxInput.absPressure, minimum: 0, maximum: maxPressure)
            userDevice.setAbsoluteAxis(code: LinuxInput.absDistance, minimum: 0, maximum: 1)
            userDevice.setAbsoluteAxis(code: LinuxInput.absTiltX, minimum: -90, maximum: 90)
            userDevice.setAbsoluteAxis(code: LinuxInput.absTiltY, minimum: -90, maximum: 90)

            try userDevice.write(to: fd)
        }

        guard linuxIoctl(fd, LinuxInput.uiDevCreate) == 0 else {
            throw ServerError.posix("UI_DEV_CREATE", errno)
        }
    }

    private func configureWithModernUInput() throws -> Bool {
        var setup = UInputSetupBuffer(name: Self.deviceName)
        setup.setInputID(busType: LinuxInput.busVirtual, vendor: 0x1701, product: 0x1701, version: 1)

        try setupAxis(code: LinuxInput.absX, minimum: 0, maximum: maxX, resolution: 12)
        try setupAxis(code: LinuxInput.absY, minimum: 0, maximum: maxY, resolution: 12)
        try setupAxis(code: LinuxInput.absPressure, minimum: 0, maximum: maxPressure, resolution: 12)
        try setupAxis(code: LinuxInput.absDistance, minimum: 0, maximum: 1, resolution: 0)
        try setupAxis(code: LinuxInput.absTiltX, minimum: -90, maximum: 90, resolution: 12)
        try setupAxis(code: LinuxInput.absTiltY, minimum: -90, maximum: 90, resolution: 12)

        guard linuxIoctlBytes(fd, LinuxInput.uiDevSetup, &setup.bytes) == 0 else {
            if errno == EINVAL {
                return false
            }
            throw ServerError.posix("UI_DEV_SETUP", errno)
        }

        return true
    }

    private func setupAxis(code: Int32, minimum: Int32, maximum: Int32, resolution: Int32) throws {
        var axis = UInputAbsSetupBuffer(code: code, minimum: minimum, maximum: maximum, resolution: resolution)
        guard linuxIoctlBytes(fd, LinuxInput.uiAbsSetup, &axis.bytes) == 0 else {
            throw ServerError.posix("UI_ABS_SETUP", errno)
        }
    }

    private func setBit(request: UInt, value: Int32) throws {
        guard linuxIoctl(fd, request, value) == 0 else {
            throw ServerError.posix("ioctl", errno)
        }
    }

    private func setString(request: UInt, value: String) throws {
        guard linuxIoctlString(fd, request, value) == 0 else {
            throw ServerError.posix("ioctl string", errno)
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

    private func setActiveTool(_ tool: PencilTool) throws {
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolPen, value: tool == .pen ? 1 : 0)
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolRubber, value: tool == .eraser ? 1 : 0)
        activeTool = tool
    }

    private var hasActiveState: Bool {
        isTouching || activeTool != nil
    }

    private static func timestampValue(_ timestamp: UInt64) -> Int32 {
        Int32(timestamp % (UInt64(Int32.max) + 1))
    }

    static let deviceName = "InkWand Virtual Pen"
}

struct UInputSetupBuffer {
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

struct UInputAbsSetupBuffer {
    private static let byteCount = 28

    var bytes = [UInt8](repeating: 0, count: byteCount)

    init(code: Int32, minimum: Int32, maximum: Int32, resolution: Int32) {
        setUInt16(UInt16(code), at: 0)
        setInt32(0, at: 4)
        setInt32(minimum, at: 8)
        setInt32(maximum, at: 12)
        setInt32(0, at: 16)
        setInt32(0, at: 20)
        setInt32(resolution, at: 24)
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

private struct UInputUserDeviceBuffer {
    private static let byteCount = 80 + 8 + 4 + (64 * 4 * 4)
    private static let inputIDOffset = 80
    private static let ffEffectsOffset = 88
    private static let absMaxOffset = 92
    private static let absMinOffset = absMaxOffset + 64 * 4
    private static let absFuzzOffset = absMinOffset + 64 * 4
    private static let absFlatOffset = absFuzzOffset + 64 * 4

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

    mutating func setAbsoluteAxis(code: Int32, minimum: Int32, maximum: Int32) {
        let index = Int(code)
        setInt32(maximum, at: Self.absMaxOffset + index * 4)
        setInt32(minimum, at: Self.absMinOffset + index * 4)
        setInt32(0, at: Self.absFuzzOffset + index * 4)
        setInt32(0, at: Self.absFlatOffset + index * 4)
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
