import Foundation
import InkWandCore

protocol PenInputDevice: AnyObject {
    var isTouchActive: Bool { get }
    var keepsToolInProximityAfterLift: Bool { get }

    func emitDownOrMove(_ event: MappedPenEvent) throws
    @discardableResult
    func release(timestamp: UInt64) throws -> Bool
    func switchTool(to tool: PencilTool, timestamp: UInt64) throws
    func releaseIfStale(minimumAge: TimeInterval, timestamp: UInt64) throws -> Bool
    func releaseHover(timestamp: UInt64) throws -> Bool
    func liftTouch(tool: PencilTool, timestamp: UInt64) throws
    func destroy()
}

protocol TouchInputDevice: AnyObject {
    var shouldReleasePenBeforeTouchInput: Bool { get }
    var shouldProcessTouchInput: Bool { get }
    func emitFrame(_ samples: [TouchSample]) throws
    func release(timestamp: UInt64) throws
    func destroy()
}

extension TouchInputDevice {
    var shouldReleasePenBeforeTouchInput: Bool { true }
    var shouldProcessTouchInput: Bool { true }
}

extension PenInputDevice {
    var keepsToolInProximityAfterLift: Bool { true }
}

protocol PadInputDevice: AnyObject {
    func emit(_ action: PadAction) throws
    func release() throws
    func destroy()
}

protocol DesktopInputMapper: AnyObject {
    func mapStylusIfNeeded()
    func mapTouchIfNeeded()
}

struct InputDeviceSet {
    var pen: PenInputDevice
    var touch: TouchInputDevice
    var pad: PadInputDevice
    var mapper: DesktopInputMapper
}

#if os(Linux)
extension UInputPenDevice: PenInputDevice {}
extension UInputTouchDevice: TouchInputDevice {}
extension UInputPadDevice: PadInputDevice {}
extension XInputDeviceMapper: DesktopInputMapper {}
#endif
