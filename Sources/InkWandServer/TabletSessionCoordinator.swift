#if os(Linux)
import Foundation
import InkWandCore

final class TabletSessionCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let mapper = TabletMapper()
    private let device: UInputPenDevice
    private let padDevice: UInputPadDevice
    private let touchDevice: UInputTouchDevice
    private let inputMapper: XInputDeviceMapper
    private let verbose: Bool
    private let stalePenReleaseMinimumAge: TimeInterval = 0.05
    private let inputSettleDelay: TimeInterval = 0.015
    private var activeSessionID = UUID()
    private var activeTransport = "none"
    private var didReceiveHello = false
    private var activeTool: PencilTool?
    private var inputCounters = InputCounters()

    init(
        device: UInputPenDevice,
        padDevice: UInputPadDevice,
        touchDevice: UInputTouchDevice,
        verbose: Bool
    ) {
        self.device = device
        self.padDevice = padDevice
        self.touchDevice = touchDevice
        self.inputMapper = XInputDeviceMapper(verbose: verbose)
        self.verbose = verbose
    }

    var maxX: Int32 { mapper.maxX }
    var maxY: Int32 { mapper.maxY }
    var maxPressure: Int32 { mapper.maxPressure }

    @discardableResult
    func runSession(_ client: TabletClient, transport: String) -> Bool {
        var sessionID: UUID?

        do {
            try client.readMessages { [weak self] message in
                guard let self else { return }

                if case .hello = message, sessionID == nil {
                    sessionID = self.beginSession(transport: transport)
                }

                guard let activeSessionID = sessionID else {
                    if self.verbose {
                        ServerLog.info("ignoring \(transport) message before hello")
                    }
                    return
                }

                try self.handle(message, sessionID: activeSessionID, transport: transport)
            }
        } catch {
            if verbose, sessionID != nil {
                ServerLog.info("\(transport) session ended: \(error)")
            }
        }

        client.close()
        if let sessionID {
            endSession(sessionID)
            return true
        }

        return false
    }

    func releaseAndDestroy() {
        lock.lock()
        defer { lock.unlock() }
        _ = try? device.release()
        try? padDevice.release()
        try? touchDevice.release()
        device.destroy()
        padDevice.destroy()
        touchDevice.destroy()
    }

    private func beginSession(transport: String) -> UUID {
        lock.lock()
        defer { lock.unlock() }

        activeSessionID = UUID()
        activeTransport = transport
        didReceiveHello = false
        inputCounters = InputCounters()
        _ = try? device.release()
        try? padDevice.release()
        try? touchDevice.release()
        activeTool = nil

        ServerLog.info("Accepted \(transport) tablet session.")
        return activeSessionID
    }

    private func endSession(_ sessionID: UUID) {
        lock.lock()
        defer { lock.unlock() }

        guard sessionID == activeSessionID else {
            return
        }

        _ = try? device.release()
        try? padDevice.release()
        try? touchDevice.release()
        logSessionSummary()
        didReceiveHello = false
        activeTransport = "none"
        activeTool = nil
        ServerLog.info("Tablet session disconnected.")
    }

    private func handle(_ message: InkMessage, sessionID: UUID, transport: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard sessionID == activeSessionID else {
            return
        }

        switch message {
        case let .hello(hello):
            didReceiveHello = true
            ServerLog.info("Connected to \(hello.deviceName) via \(transport) (\(Int(hello.canvasWidth))x\(Int(hello.canvasHeight))).")

        case let .sample(sample):
            guard didReceiveHello else {
                if verbose {
                    ServerLog.info("ignoring \(transport) sample before hello")
                }
                return
            }
            inputMapper.mapStylusIfNeeded()
            let event = mapper.map(sample)
            inputCounters.samples += 1

            if sample.phase == .ended || sample.phase == .cancelled {
                try device.liftTouch(tool: sample.tool, timestamp: sample.timestamp)
                activeTool = sample.tool

                if verbose {
                    ServerLog.info("sample \(sample.phase.rawValue) lift transport=\(activeTransport)")
                }
                return
            }

            if sample.phase == .began {
                try touchDevice.release()
                if let activeTool, activeTool != sample.tool {
                    try device.switchTool(to: sample.tool, timestamp: sample.timestamp)
                }
                activeTool = sample.tool
            }

            try device.emitDownOrMove(event)

            if verbose {
                ServerLog.info("sample \(sample.phase.rawValue) tool=\(event.tool.rawValue) x=\(event.x) y=\(event.y) p=\(event.pressure) tx=\(event.tiltX) ty=\(event.tiltY) transport=\(activeTransport)")
            }

        case .cancel:
            try device.release()
            try touchDevice.release()
            try padDevice.release()
            inputCounters.cancels += 1
            logInputEvent("cancel transport=\(activeTransport)")

        case let .tool(tool):
            guard didReceiveHello else {
                if verbose {
                    ServerLog.info("ignoring \(transport) tool before hello")
                }
                return
            }

            activeTool = tool
            try touchDevice.release()
            try device.switchTool(to: tool)
            inputCounters.tools += 1

            if verbose {
                ServerLog.info("tool \(tool.rawValue) transport=\(activeTransport)")
            }

        case let .pad(action):
            guard didReceiveHello else {
                if verbose {
                    ServerLog.info("ignoring \(transport) pad before hello")
                }
                return
            }

            try prepareForPadAction(action)
            try padDevice.emit(action)
            inputCounters.pads += 1
            logInputEvent("pad \(action.rawValue) transport=\(activeTransport)")

            if verbose {
                ServerLog.info("pad \(action.rawValue) transport=\(activeTransport)")
            }

        case let .gesture(gesture):
            guard didReceiveHello else {
                if verbose {
                    ServerLog.info("ignoring \(transport) gesture before hello")
                }
                return
            }

            if gesture.phase == .began || gesture.phase == .moved {
                try releasePenBeforeTouch(timestamp: gesture.timestamp, reason: "gesture \(gesture.phase.rawValue)")
            }
            inputMapper.mapTouchIfNeeded()
            try touchDevice.emitLegacyGesture(gesture)
            inputCounters.gestures += 1
            if gesture.phase != .moved {
                logInputEvent("gesture \(gesture.phase.rawValue) transport=\(activeTransport)")
            }

            if verbose {
                ServerLog.info("gesture \(gesture.phase.rawValue) x=\(gesture.x) y=\(gesture.y) tx=\(gesture.translationX) ty=\(gesture.translationY) scale=\(gesture.scale) rotation=\(gesture.rotation) transport=\(activeTransport)")
            }

        case let .touch(touch):
            guard didReceiveHello else {
                if verbose {
                    ServerLog.info("ignoring \(transport) touch before hello")
                }
                return
            }

            try handleTouchFrame([touch])

        case let .touchFrame(touches):
            guard didReceiveHello else {
                if verbose {
                    ServerLog.info("ignoring \(transport) touch frame before hello")
                }
                return
            }

            try handleTouchFrame(touches)
        }
    }

    private func handleTouchFrame(_ touches: [TouchSample]) throws {
        guard !touches.isEmpty else { return }

        if let touch = touches.first(where: { $0.phase == .began || $0.phase == .moved }) {
            try releasePenBeforeTouch(timestamp: touch.timestamp, reason: "touch \(touch.phase.rawValue)")
        }

        inputMapper.mapTouchIfNeeded()
        try touchDevice.emitFrame(touches)
        inputCounters.touches += touches.count

        for touch in touches where touch.phase != .moved {
            logInputEvent("touch \(touch.phase.rawValue) id=\(touch.id) transport=\(activeTransport)")
        }

        if verbose {
            for touch in touches {
                ServerLog.info("touch \(touch.phase.rawValue) id=\(touch.id) x=\(touch.x) y=\(touch.y) p=\(touch.pressure) w=\(touch.width) h=\(touch.height) transport=\(activeTransport)")
            }
        }
    }

    private func prepareForPadAction(_ action: PadAction) throws {
        switch action {
        case .undo, .redo, .brushSmaller, .brushLarger, .opacityLower, .opacityHigher:
            let releasedPen = try device.release()
            try touchDevice.release()
            try padDevice.release()
            if releasedPen {
                Thread.sleep(forTimeInterval: inputSettleDelay)
                logStateRepair("released active pen before pad \(action.rawValue)")
            }

        case .panBegan:
            try touchDevice.release()
            try padDevice.release()
            let releasedPen = try device.releaseIfStale(minimumAge: stalePenReleaseMinimumAge)
            if releasedPen {
                Thread.sleep(forTimeInterval: inputSettleDelay)
                logStateRepair("released stale pen before pad \(action.rawValue)")
            }

        case .panEnded:
            break
        }
    }

    private func releasePenBeforeTouch(timestamp: UInt64, reason: String) throws {
        let releasedHover = try device.releaseHover(timestamp: timestamp)
        if releasedHover {
            Thread.sleep(forTimeInterval: inputSettleDelay)
            logStateRepair("released hover pen before \(reason)")
            return
        }

        let releasedPen = try device.release(timestamp: timestamp)
        guard releasedPen else { return }

        Thread.sleep(forTimeInterval: inputSettleDelay)
        logStateRepair("released pen before \(reason)")
    }

    private func logStateRepair(_ message: String) {
        if verbose {
            ServerLog.info("\(message) transport=\(activeTransport)")
        }
    }

    private func logInputEvent(_ message: String) {
        guard !verbose else { return }
        ServerLog.info(message)
    }

    private func logSessionSummary() {
        guard !verbose, inputCounters.hasInput else { return }
        ServerLog.info(
            "session input summary samples=\(inputCounters.samples) touches=\(inputCounters.touches) gestures=\(inputCounters.gestures) pads=\(inputCounters.pads) tools=\(inputCounters.tools) cancels=\(inputCounters.cancels)"
        )
    }

}

private struct InputCounters {
    var samples = 0
    var touches = 0
    var gestures = 0
    var pads = 0
    var tools = 0
    var cancels = 0

    var hasInput: Bool {
        samples + touches + gestures + pads + tools + cancels > 0
    }
}
#endif
