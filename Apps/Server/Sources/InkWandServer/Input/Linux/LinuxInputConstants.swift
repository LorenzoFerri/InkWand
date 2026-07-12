#if os(Linux)
import Glibc

enum LinuxInput {
    static let evSyn: Int32 = 0x00
    static let evKey: Int32 = 0x01
    static let evAbs: Int32 = 0x03
    static let evMsc: Int32 = 0x04

    static let synReport: Int32 = 0

    static let btnTouch: Int32 = 0x14a
    static let btnToolPen: Int32 = 0x140
    static let btnToolRubber: Int32 = 0x141
    static let btnToolFinger: Int32 = 0x145
    static let btnStylus: Int32 = 0x14b
    static let btnStylus2: Int32 = 0x14c
    static let btnToolDoubleTap: Int32 = 0x14d
    static let btnToolTripleTap: Int32 = 0x14e
    static let btnToolQuadTap: Int32 = 0x14f
    static let btnToolQuintTap: Int32 = 0x148

    static let keyLeftCtrl: Int32 = 0x1d
    static let keyLeftShift: Int32 = 0x2a
    static let keyZ: Int32 = 0x2c
    static let keyI: Int32 = 0x17
    static let keyO: Int32 = 0x18
    static let keySpace: Int32 = 0x39
    static let keyLeftBrace: Int32 = 0x1a
    static let keyRightBrace: Int32 = 0x1b
    static let keyEsc: Int32 = 0x01
    static let keyMicMute: Int32 = 0xf8

    static let absX: Int32 = 0x00
    static let absY: Int32 = 0x01
    static let absPressure: Int32 = 0x18
    static let absDistance: Int32 = 0x19
    static let absTiltX: Int32 = 0x1a
    static let absTiltY: Int32 = 0x1b
    static let absMisc: Int32 = 0x28
    static let absMtSlot: Int32 = 0x2f
    static let absMtTouchMajor: Int32 = 0x30
    static let absMtTouchMinor: Int32 = 0x31
    static let absMtOrientation: Int32 = 0x34
    static let absMtPositionX: Int32 = 0x35
    static let absMtPositionY: Int32 = 0x36
    static let absMtTrackingID: Int32 = 0x39
    static let absMtPressure: Int32 = 0x3a

    static let mscSerial: Int32 = 0x00
    static let mscTimestamp: Int32 = 0x05

    static let inputPropDirect: Int32 = 0x01

    static let busUSB: UInt16 = 0x03
    static let busVirtual: UInt16 = 0x06

    static let uiDevCreate: UInt = 0x5501
    static let uiDevDestroy: UInt = 0x5502
    static let uiDevSetup: UInt = 0x405C5503
    static let uiAbsSetup: UInt = 0x401C5504
    static let uiSetEvBit: UInt = 0x40045564
    static let uiSetKeyBit: UInt = 0x40045565
    static let uiSetAbsBit: UInt = 0x40045567
    static let uiSetMscBit: UInt = 0x40045568
    static let uiSetPhys: UInt = 0x4008556C
    static let uiSetPropBit: UInt = 0x4004556E

}

struct LinuxInputEvent {
    var time: timeval
    var type: UInt16
    var code: UInt16
    var value: Int32

    init(type: Int32, code: Int32, value: Int32) {
        self.time = timeval(tv_sec: 0, tv_usec: 0)
        self.type = UInt16(type)
        self.code = UInt16(code)
        self.value = value
    }
}

@_silgen_name("ioctl")
private func c_ioctl(_ fd: Int32, _ request: UInt, _ value: UInt) -> Int32

@discardableResult
func linuxIoctl(_ fd: Int32, _ request: UInt, _ value: Int32 = 0) -> Int32 {
    c_ioctl(fd, request, UInt(bitPattern: Int(value)))
}

@discardableResult
func linuxIoctlPointer<T>(_ fd: Int32, _ request: UInt, _ value: inout T) -> Int32 {
    withUnsafeMutablePointer(to: &value) { pointer in
        c_ioctl(fd, request, UInt(bitPattern: pointer))
    }
}

@discardableResult
func linuxIoctlBytes(_ fd: Int32, _ request: UInt, _ bytes: inout [UInt8]) -> Int32 {
    bytes.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress else {
            errno = EINVAL
            return -1
        }
        return c_ioctl(fd, request, UInt(bitPattern: baseAddress))
    }
}

@discardableResult
func linuxIoctlString(_ fd: Int32, _ request: UInt, _ value: String) -> Int32 {
    value.withCString { pointer in
        c_ioctl(fd, request, UInt(bitPattern: pointer))
    }
}
#endif
