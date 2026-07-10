#if os(Linux)
import Foundation
import Glibc
import InkWandCore

final class UInputTouchDevice {
    private let fd: Int32
    private let maxX: Int32
    private let maxY: Int32
    private let maxPressure: Int32
    private let name: String
    private let physicalPath: String
    private var isDestroyed = false
    private var touches = Array<TrackedTouch?>(repeating: nil, count: 5)
    private var nextTrackingID: Int32 = 1

    init(
        maxX: Int32,
        maxY: Int32,
        maxPressure: Int32 = 65535,
        name: String = UInputTouchDevice.deviceName,
        physicalPath: String = "inkwand/touch"
    ) throws {
        self.maxX = maxX
        self.maxY = maxY
        self.maxPressure = maxPressure
        self.name = name
        self.physicalPath = physicalPath

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

    func emit(_ sample: TouchSample) throws {
        try emitFrame([sample])
    }

    func emitFrame(_ samples: [TouchSample]) throws {
        guard !samples.isEmpty else { return }

        var releasedSlots: [Int: UInt64] = [:]
        for sample in samples {
            apply(sample, releasedSlots: &releasedSlots)
        }
        try emitCurrentFrame(releasedSlots: releasedSlots, timestamp: samples.last?.timestamp ?? 0)
    }

    private func apply(_ sample: TouchSample, releasedSlots: inout [Int: UInt64]) {
        switch sample.phase {
        case .began, .moved:
            guard let slot = existingSlot(for: sample.id) ?? assignSlot(for: sample) else {
                return
            }
            touches[slot]?.sample = sample
        case .ended, .cancelled:
            guard let slot = existingSlot(for: sample.id) else { return }
            releasedSlots[slot] = sample.timestamp
            touches[slot] = nil
        }
    }

    func release(timestamp: UInt64 = 0) throws {
        var didRelease = false
        for slot in 0..<Self.slotCount where touches[slot] != nil {
            try releaseSlot(slot, timestamp: timestamp)
            didRelease = true
        }
        if didRelease {
            try sync()
        }
    }

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true

        try? release()
        _ = linuxIoctl(fd, LinuxInput.uiDevDestroy)
        _ = Glibc.close(fd)
    }

    private func emitCurrentFrame(releasedSlots: [Int: UInt64], timestamp: UInt64) throws {
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnTouch, value: activeTouchCount > 0 ? 1 : 0)
        try setTouchCount(activeTouchCount)

        for slot in releasedSlots.keys.sorted() {
            try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtSlot, value: Int32(slot))
            try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtTrackingID, value: -1)
            try writeEvent(type: LinuxInput.evMsc, code: LinuxInput.mscTimestamp, value: Self.timestampValue(releasedSlots[slot] ?? timestamp))
        }

        for slot in 0..<Self.slotCount {
            guard let touch = touches[slot] else { continue }
            try emitSlot(slot, touch: touch)
        }

        try writeEvent(type: LinuxInput.evMsc, code: LinuxInput.mscTimestamp, value: Self.timestampValue(timestamp))
        try sync()
    }

    private func emitSlot(_ slot: Int, touch: TrackedTouch) throws {
        let sample = touch.sample

        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtSlot, value: Int32(slot))
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtTrackingID, value: touch.trackingID)

        let major: Int32
        let minor: Int32
        let orientation: Int32
        if sample.height >= sample.width {
            major = map(sample.height, maximum: maxPressure)
            minor = map(sample.width, maximum: maxPressure)
            orientation = 0
        } else {
            major = map(sample.width, maximum: maxPressure)
            minor = map(sample.height, maximum: maxPressure)
            orientation = 1
        }

        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtPressure, value: map(sample.pressure, maximum: maxPressure))
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtTouchMajor, value: major)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtTouchMinor, value: minor)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtOrientation, value: orientation)
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtPositionX, value: map(sample.x, maximum: maxX))
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtPositionY, value: map(sample.y, maximum: maxY))
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absX, value: map(sample.x, maximum: maxX))
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absY, value: map(sample.y, maximum: maxY))
        try writeEvent(type: LinuxInput.evMsc, code: LinuxInput.mscTimestamp, value: Self.timestampValue(sample.timestamp))
    }

    private func releaseSlot(_ slot: Int, timestamp: UInt64) throws {
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtSlot, value: Int32(slot))
        try writeEvent(type: LinuxInput.evAbs, code: LinuxInput.absMtTrackingID, value: -1)
        touches[slot] = nil
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnTouch, value: activeTouchCount > 0 ? 1 : 0)
        try setTouchCount(activeTouchCount)
        try writeEvent(type: LinuxInput.evMsc, code: LinuxInput.mscTimestamp, value: Self.timestampValue(timestamp))
    }

    private func existingSlot(for id: UInt64) -> Int? {
        touches.firstIndex { $0?.id == id }
    }

    private func assignSlot(for sample: TouchSample) -> Int? {
        guard let slot = touches.firstIndex(where: { $0 == nil }) else {
            return nil
        }
        touches[slot] = TrackedTouch(id: sample.id, trackingID: allocateTrackingID(), sample: sample)
        return slot
    }

    private func allocateTrackingID() -> Int32 {
        var candidate = nextTrackingID
        while touches.contains(where: { $0?.trackingID == candidate }) {
            candidate = candidate == Self.maxTrackingID ? 1 : candidate + 1
        }
        nextTrackingID = candidate == Self.maxTrackingID ? 1 : candidate + 1
        return candidate
    }

    private var activeTouchCount: Int {
        touches.filter { $0 != nil }.count
    }

    private func setTouchCount(_ count: Int) throws {
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolFinger, value: count == 1 ? 1 : 0)
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolDoubleTap, value: count == 2 ? 1 : 0)
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolTripleTap, value: count == 3 ? 1 : 0)
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolQuadTap, value: count == 4 ? 1 : 0)
        try writeEvent(type: LinuxInput.evKey, code: LinuxInput.btnToolQuintTap, value: count >= 5 ? 1 : 0)
    }

    private func map(_ value: Double, maximum: Int32) -> Int32 {
        Int32((min(max(value, 0), 1) * Double(maximum)).rounded())
    }

    private func configure() throws {
        try setString(request: LinuxInput.uiSetPhys, value: physicalPath)

        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evKey)
        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evAbs)
        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evMsc)
        try setBit(request: LinuxInput.uiSetEvBit, value: LinuxInput.evSyn)
        _ = linuxIoctl(fd, LinuxInput.uiSetPropBit, LinuxInput.inputPropDirect)

        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnTouch)
        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnToolFinger)
        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnToolDoubleTap)
        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnToolTripleTap)
        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnToolQuadTap)
        try setBit(request: LinuxInput.uiSetKeyBit, value: LinuxInput.btnToolQuintTap)
        try setBit(request: LinuxInput.uiSetMscBit, value: LinuxInput.mscTimestamp)

        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absX)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absY)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absMtSlot)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absMtTrackingID)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absMtPositionX)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absMtPositionY)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absMtPressure)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absMtTouchMajor)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absMtTouchMinor)
        try setBit(request: LinuxInput.uiSetAbsBit, value: LinuxInput.absMtOrientation)

        if try !configureWithModernUInput() {
            var userDevice = UInputTouchUserDeviceBuffer(name: name)
            userDevice.setInputID(busType: LinuxInput.busVirtual, vendor: 0x1701, product: 0x1701, version: 1)
            userDevice.setAbsoluteAxis(code: LinuxInput.absX, minimum: 0, maximum: maxX)
            userDevice.setAbsoluteAxis(code: LinuxInput.absY, minimum: 0, maximum: maxY)
            userDevice.setAbsoluteAxis(code: LinuxInput.absMtSlot, minimum: 0, maximum: Self.maxSlot)
            userDevice.setAbsoluteAxis(code: LinuxInput.absMtTrackingID, minimum: 0, maximum: Self.maxTrackingID)
            userDevice.setAbsoluteAxis(code: LinuxInput.absMtPositionX, minimum: 0, maximum: maxX)
            userDevice.setAbsoluteAxis(code: LinuxInput.absMtPositionY, minimum: 0, maximum: maxY)
            userDevice.setAbsoluteAxis(code: LinuxInput.absMtPressure, minimum: 0, maximum: maxPressure)
            userDevice.setAbsoluteAxis(code: LinuxInput.absMtTouchMajor, minimum: 0, maximum: maxPressure)
            userDevice.setAbsoluteAxis(code: LinuxInput.absMtTouchMinor, minimum: 0, maximum: maxPressure)
            userDevice.setAbsoluteAxis(code: LinuxInput.absMtOrientation, minimum: 0, maximum: 1)
            try userDevice.write(to: fd)
        }

        guard linuxIoctl(fd, LinuxInput.uiDevCreate) == 0 else {
            throw ServerError.posix("UI_DEV_CREATE", errno)
        }
    }

    private func configureWithModernUInput() throws -> Bool {
        var setup = UInputSetupBuffer(name: name)
        setup.setInputID(busType: LinuxInput.busVirtual, vendor: 0x1701, product: 0x1701, version: 1)

        try setupAxis(code: LinuxInput.absX, minimum: 0, maximum: maxX, resolution: 200)
        try setupAxis(code: LinuxInput.absY, minimum: 0, maximum: maxY, resolution: 200)
        try setupAxis(code: LinuxInput.absMtSlot, minimum: 0, maximum: Self.maxSlot, resolution: 0)
        try setupAxis(code: LinuxInput.absMtTrackingID, minimum: 0, maximum: Self.maxTrackingID, resolution: 0)
        try setupAxis(code: LinuxInput.absMtPositionX, minimum: 0, maximum: maxX, resolution: 200)
        try setupAxis(code: LinuxInput.absMtPositionY, minimum: 0, maximum: maxY, resolution: 200)
        try setupAxis(code: LinuxInput.absMtPressure, minimum: 0, maximum: maxPressure, resolution: 0)
        try setupAxis(code: LinuxInput.absMtTouchMajor, minimum: 0, maximum: maxPressure, resolution: 12)
        try setupAxis(code: LinuxInput.absMtTouchMinor, minimum: 0, maximum: maxPressure, resolution: 12)
        try setupAxis(code: LinuxInput.absMtOrientation, minimum: 0, maximum: 1, resolution: 0)

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

    private static func timestampValue(_ timestamp: UInt64) -> Int32 {
        Int32(timestamp % (UInt64(Int32.max) + 1))
    }

    static let deviceName = "InkWand Touch Surface"
    private static let slotCount = 5
    private static let maxSlot: Int32 = 4
    private static let maxTrackingID: Int32 = 65_535
    private static let defaultTouchSize = 0.01
}

private struct TrackedTouch: Equatable {
    var id: UInt64
    var trackingID: Int32
    var sample: TouchSample
}

private struct UInputTouchUserDeviceBuffer {
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
