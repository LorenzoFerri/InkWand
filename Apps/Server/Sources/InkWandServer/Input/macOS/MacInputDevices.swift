#if os(macOS)
@preconcurrency import CoreGraphics
import Foundation
import InkWandCore

final class MacTabletEventPenDevice: PenInputDevice {
    let keepsToolInProximityAfterLift = true
    var isTouchActive: Bool { isTouching }

    private let eventSource = CGEventSource(stateID: .privateState)
    private let eventQueue = DispatchQueue(label: "app.inkwand.server.mac-tablet-events", qos: .userInteractive)
    private let maxX: Int32
    private let maxY: Int32
    private let maxPressure: Int32
    private var activeTool: PencilTool?
    private var lastEvent: MappedPenEvent?
    private var lastEventDate = Date.distantPast
    private var isTouching = false
    private var didLogFirstPointer = false

    init(maxX: Int32, maxY: Int32, maxPressure: Int32) {
        self.maxX = max(maxX, 1)
        self.maxY = max(maxY, 1)
        self.maxPressure = max(maxPressure, 1)
    }

    func emitDownOrMove(_ event: MappedPenEvent) throws {
        let didChangeTool = activeTool != event.tool
        if activeTool == nil || didChangeTool {
            if let activeTool {
                postProximity(enter: false, tool: activeTool)
            }
            postProximity(enter: true, tool: event.tool)
        }
        activeTool = event.tool
        lastEvent = event
        lastEventDate = Date()
        postPointer(event)
        isTouching = event.isTouching
    }

    @discardableResult
    func release(timestamp: UInt64) throws -> Bool {
        guard activeTool != nil || lastEvent != nil else { return false }
        postPointer(releaseEvent(timestamp: timestamp))
        postProximity(enter: false, tool: activeTool ?? lastEvent?.tool ?? .pen)
        activeTool = nil
        lastEvent = nil
        isTouching = false
        lastEventDate = Date()
        return true
    }

    func switchTool(to tool: PencilTool, timestamp: UInt64) throws {
        if let activeTool, activeTool != tool {
            postProximity(enter: false, tool: activeTool)
        }
        if activeTool != tool {
            postProximity(enter: true, tool: tool)
        }
        activeTool = tool
    }

    func releaseIfStale(minimumAge: TimeInterval, timestamp: UInt64) throws -> Bool {
        guard (activeTool != nil || lastEvent != nil), Date().timeIntervalSince(lastEventDate) >= minimumAge else {
            return false
        }
        return try release(timestamp: timestamp)
    }

    func releaseHover(timestamp: UInt64) throws -> Bool {
        guard activeTool != nil, lastEvent?.isTouching != true else { return false }
        postProximity(enter: false, tool: activeTool ?? .pen)
        activeTool = nil
        lastEventDate = Date()
        return true
    }

    func liftTouch(tool: PencilTool, timestamp: UInt64) throws {
        guard isTouching else { return }
        let event = releaseEvent(tool: tool, timestamp: timestamp)
        activeTool = tool
        lastEventDate = Date()
        postPointer(event)
        isTouching = false
        lastEvent = event
    }

    func destroy() {
        _ = try? release(timestamp: 0)
    }

    private func postPointer(_ mappedEvent: MappedPenEvent) {
        let point = screenPoint(for: mappedEvent)
        if !didLogFirstPointer {
            didLogFirstPointer = true
            ServerLog.info("Posting first macOS tablet pointer cgPost=\(CGPreflightPostEventAccess()) point=(\(Int(point.x)),\(Int(point.y))) touching=\(mappedEvent.isTouching) pressure=\(mappedEvent.pressure)")
        }
        postMouseSubtypePointer(mappedEvent, point: point)
    }

    private func postMouseSubtypePointer(_ mappedEvent: MappedPenEvent, point: CGPoint) {
        let type = Self.mouseEventType(wasTouching: isTouching, isTouching: mappedEvent.isTouching)

        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        event.setIntegerValueField(.mouseEventClickState, value: type == .mouseMoved ? 0 : 1)
        event.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        populateTabletFields(on: event, event: mappedEvent)
        post(event)
    }

    static func mouseEventType(wasTouching: Bool, isTouching: Bool) -> CGEventType {
        switch (wasTouching, isTouching) {
        case (false, true):
            .leftMouseDown
        case (true, true):
            .leftMouseDragged
        case (true, false):
            .leftMouseUp
        case (false, false):
            .mouseMoved
        }
    }

    private func populateTabletFields(on event: CGEvent, event mappedEvent: MappedPenEvent) {
        let pressure = Double(mappedEvent.pressure) / Double(maxPressure)
        event.setIntegerValueField(.tabletEventPointX, value: Int64(mappedEvent.x))
        event.setIntegerValueField(.tabletEventPointY, value: Int64(mappedEvent.y))
        event.setIntegerValueField(.tabletEventPointZ, value: 0)
        event.setIntegerValueField(.tabletEventPointButtons, value: mappedEvent.isTouching ? 1 : 0)
        event.setDoubleValueField(.mouseEventPressure, value: mappedEvent.isTouching ? pressure : 0)
        event.setDoubleValueField(.tabletEventPointPressure, value: mappedEvent.isTouching ? pressure : 0)
        event.setDoubleValueField(.tabletEventTiltX, value: Double(mappedEvent.tiltX) / 90.0)
        event.setDoubleValueField(.tabletEventTiltY, value: -Double(mappedEvent.tiltY) / 90.0)
        event.setIntegerValueField(.tabletEventDeviceID, value: Self.deviceID)
        event.setIntegerValueField(.tabletEventVendor1, value: mappedEvent.tool == .eraser ? 1 : 0)
    }

    private func postProximity(enter: Bool, tool: PencilTool) {
        guard let event = CGEvent(source: eventSource) else { return }
        if enter {
            ServerLog.info("Posting macOS tablet proximity tool=\(tool.rawValue)")
        }
        event.type = .tabletProximity
        populateProximityFields(on: event, enter: enter, tool: tool)
        post(event)

        guard enter else { return }
        let point = lastEvent.map(screenPoint(for:)) ?? CGEvent(source: nil)?.location ?? .zero
        guard let mouseEvent = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        mouseEvent.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletProximity.rawValue))
        populateProximityFields(on: mouseEvent, enter: true, tool: tool)
        post(mouseEvent)
    }

    private func post(_ event: CGEvent) {
        eventQueue.async {
            event.post(tap: .cghidEventTap)
        }
    }

    private func populateProximityFields(on event: CGEvent, enter: Bool, tool: PencilTool) {
        event.setIntegerValueField(.tabletProximityEventVendorID, value: Self.vendorID)
        event.setIntegerValueField(.tabletProximityEventTabletID, value: Self.productID)
        event.setIntegerValueField(.tabletProximityEventPointerID, value: tool == .eraser ? 2 : 1)
        event.setIntegerValueField(.tabletProximityEventDeviceID, value: Self.deviceID)
        event.setIntegerValueField(.tabletProximityEventSystemTabletID, value: Self.tabletID)
        event.setIntegerValueField(.tabletProximityEventVendorPointerType, value: Self.vendorPointerType)
        event.setIntegerValueField(.tabletProximityEventCapabilityMask, value: Self.capabilityMask)
        event.setIntegerValueField(.tabletProximityEventPointerType, value: tool == .eraser ? Self.eraserPointerType : Self.penPointerType)
        event.setIntegerValueField(.tabletProximityEventEnterProximity, value: enter ? 1 : 0)
    }

    private func screenPoint(for event: MappedPenEvent) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let x = bounds.minX + CGFloat(event.x) / CGFloat(maxX) * bounds.width
        let y = bounds.minY + CGFloat(event.y) / CGFloat(maxY) * bounds.height
        return CGPoint(x: x, y: y)
    }

    private func releaseEvent(tool explicitTool: PencilTool? = nil, timestamp: UInt64) -> MappedPenEvent {
        MappedPenEvent(
            x: lastEvent?.x ?? 0,
            y: lastEvent?.y ?? 0,
            pressure: 0,
            tiltX: lastEvent?.tiltX ?? 0,
            tiltY: lastEvent?.tiltY ?? 0,
            tool: explicitTool ?? lastEvent?.tool ?? activeTool ?? .pen,
            isTouching: false,
            isToolPresent: false,
            timestamp: timestamp
        )
    }

    private static let vendorID: Int64 = 0x1701
    private static let productID: Int64 = 0x1701
    private static let deviceID: Int64 = 0x17010001
    private static let tabletID: Int64 = 0x17010002
    private static let vendorPointerType: Int64 = 0x802
    private static let penPointerType: Int64 = 1
    private static let eraserPointerType: Int64 = 3
    private static let capabilityMask: Int64 =
        (1 << 0) | // abs x
        (1 << 1) | // abs y
        (1 << 2) | // buttons
        (1 << 3) | // pressure
        (1 << 4) | // tilt x
        (1 << 5) | // tilt y
        (1 << 6)   // device id
}

final class MacTouchDevice: TouchInputDevice {
    private let verbose: Bool
    private var didLogUnsupported = false
    let shouldReleasePenBeforeTouchInput = false
    let shouldProcessTouchInput = false

    init(verbose: Bool) {
        self.verbose = verbose
    }

    func emitFrame(_ samples: [TouchSample]) throws {
        logUnsupportedIfNeeded()
    }

    func release(timestamp: UInt64) throws {}
    func destroy() {}

    private func logUnsupportedIfNeeded() {
        guard verbose, !didLogUnsupported else { return }
        didLogUnsupported = true
        ServerLog.info("macOS touch backend is not implemented in this version; ignoring touch gestures.")
    }
}

final class MacPadDevice: PadInputDevice {
    private var isPanning = false

    func emit(_ action: PadAction) throws {
        switch action {
        case .undo, .redo, .brushSmaller, .brushLarger, .opacityLower, .opacityHigher:
            let shortcut = MacPadShortcut.shortcut(for: action)
            tap(key: shortcut.keyCode, flags: shortcut.eventFlags)
        case .panBegan:
            guard !isPanning else { return }
            isPanning = true
            key(MacPadShortcut.shortcut(for: action).keyCode, down: true, flags: [])
        case .panEnded:
            guard isPanning else { return }
            isPanning = false
            key(MacPadShortcut.shortcut(for: action).keyCode, down: false, flags: [])
        }
    }

    func release() throws {
        if isPanning {
            key(49, down: false, flags: [])
        }
        isPanning = false
    }

    func destroy() {
        try? release()
    }

    private func tap(key code: CGKeyCode, flags: CGEventFlags) {
        key(code, down: true, flags: flags)
        key(code, down: false, flags: flags)
    }

    private func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

struct MacPadShortcut: Equatable {
    var keyCode: CGKeyCode
    var command: Bool = false
    var shift: Bool = false

    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        return flags
    }

    static func shortcut(for action: PadAction) -> MacPadShortcut {
        switch action {
        case .undo:
            return MacPadShortcut(keyCode: 6, command: true)
        case .redo:
            return MacPadShortcut(keyCode: 6, command: true, shift: true)
        case .brushSmaller:
            return MacPadShortcut(keyCode: 33)
        case .brushLarger:
            return MacPadShortcut(keyCode: 30)
        case .opacityLower:
            return MacPadShortcut(keyCode: 34)
        case .opacityHigher:
            return MacPadShortcut(keyCode: 31)
        case .panBegan, .panEnded:
            return MacPadShortcut(keyCode: 49)
        }
    }
}

final class MacInputDeviceMapper: DesktopInputMapper {
    func mapStylusIfNeeded() {}
    func mapTouchIfNeeded() {}
}
#endif
