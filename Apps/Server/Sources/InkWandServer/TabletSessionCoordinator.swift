import Dispatch
import Foundation
import InkWandCore

final class TabletSessionCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let mapper = TabletMapper()
    private let device: PenInputDevice
    private let padDevice: PadInputDevice
    private let touchDevice: TouchInputDevice
    private let inputMapper: DesktopInputMapper
    private let authenticator: TabletSessionAuthenticator
    private let verbose: Bool
    private let stalePenReleaseMinimumAge: TimeInterval = 0.05
    private let inputSettleDelay: TimeInterval = 0.015
    private var activeSessionID = UUID()
    private var activeTransport = "none"
    private var didReceiveHello = false
    private var activeTool: PencilTool?
    private var inputCounters = InputCounters()
    private var sampleTiming = PenSampleTimingDiagnostics()
    private var sessionIsActive = false

    init(
        device: PenInputDevice,
        padDevice: PadInputDevice,
        touchDevice: TouchInputDevice,
        inputMapper: DesktopInputMapper,
        authenticator: TabletSessionAuthenticator,
        verbose: Bool
    ) {
        self.device = device
        self.padDevice = padDevice
        self.touchDevice = touchDevice
        self.inputMapper = inputMapper
        self.authenticator = authenticator
        self.verbose = verbose
    }

    var maxX: Int32 { mapper.maxX }
    var maxY: Int32 { mapper.maxY }
    var maxPressure: Int32 { mapper.maxPressure }
    var hasActiveTabletSession: Bool { lock.withLock { sessionIsActive } }

    @discardableResult
    func runSession(_ client: TabletClient, transport: String) -> Bool {
        var sessionID: UUID?
        var isAuthenticated = false

        do {
            try client.readMessages { [weak self] message in
                guard let self else { return }

                if !isAuthenticated {
                    isAuthenticated = try self.authenticator.handlePreflight(message, client: client)
                    if !isAuthenticated, self.verbose {
                        ServerLog.info("rejected unauthenticated \(transport) message")
                    }
                    return
                }

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
        _ = try? device.release(timestamp: 0)
        try? padDevice.release()
        try? touchDevice.release(timestamp: 0)
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
        sampleTiming = PenSampleTimingDiagnostics()
        sessionIsActive = true
        _ = try? device.release(timestamp: 0)
        try? padDevice.release()
        try? touchDevice.release(timestamp: 0)
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

        _ = try? device.release(timestamp: 0)
        try? padDevice.release()
        try? touchDevice.release(timestamp: 0)
        logSessionSummary()
        didReceiveHello = false
        activeTransport = "none"
        activeTool = nil
        sessionIsActive = false
        ServerLog.info("Tablet session disconnected.")
    }

    private func handle(_ message: InkMessage, sessionID: UUID, transport: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard sessionID == activeSessionID else {
            return
        }

        switch message {
        case .authRequest, .authResponse, .pairingRequest, .pairingResponse, .encrypted:
            if verbose {
                ServerLog.info("ignoring \(transport) auth message after session activation")
            }

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
            if inputCounters.samples == 1 {
                ServerLog.info("First pen sample received phase=\(sample.phase.rawValue) tool=\(event.tool.rawValue) x=\(event.x) y=\(event.y) p=\(event.pressure) transport=\(transport)")
            }
            sampleTiming.record(sample: sample, mappedEvent: event, transport: transport)

            if sample.phase == .cancelled {
                guard device.isTouchActive else {
                    logInputEvent("ignored sample \(sample.phase.rawValue) without active pen transport=\(transport)")
                    return
                }
                try device.release(timestamp: sample.timestamp)
                activeTool = nil

                if verbose {
                    ServerLog.info("sample \(sample.phase.rawValue) full release transport=\(transport)")
                }
                return
            }

            if sample.phase == .ended {
                guard device.isTouchActive else {
                    logInputEvent("ignored sample \(sample.phase.rawValue) without active pen transport=\(transport)")
                    return
                }
                try device.liftTouch(tool: sample.tool, timestamp: sample.timestamp)
                activeTool = device.keepsToolInProximityAfterLift ? sample.tool : nil

                if verbose {
                    ServerLog.info("sample \(sample.phase.rawValue) lift transport=\(transport)")
                }
                return
            }

            if sample.phase == .began {
                try touchDevice.release(timestamp: sample.timestamp)
                if let activeTool, activeTool != sample.tool {
                    try device.switchTool(to: sample.tool, timestamp: sample.timestamp)
                }
                activeTool = sample.tool
            }

            try device.emitDownOrMove(event)

            if verbose {
                ServerLog.info("sample \(sample.phase.rawValue) tool=\(event.tool.rawValue) x=\(event.x) y=\(event.y) p=\(event.pressure) tx=\(event.tiltX) ty=\(event.tiltY) transport=\(transport)")
            }

        case .cancel:
            try device.release(timestamp: 0)
            try touchDevice.release(timestamp: 0)
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
            try touchDevice.release(timestamp: 0)
            try device.switchTool(to: tool, timestamp: 0)
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
            guard touchDevice.shouldProcessTouchInput else {
                inputCounters.ignoredTouches += 1
                if gesture.phase != .moved {
                    logInputEvent("ignored gesture \(gesture.phase.rawValue) transport=\(activeTransport)")
                }
                return
            }

            if gesture.phase == .began || gesture.phase == .moved {
                if touchDevice.shouldReleasePenBeforeTouchInput {
                    try releasePenBeforeTouch(timestamp: gesture.timestamp, reason: "gesture \(gesture.phase.rawValue)")
                }
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
        guard touchDevice.shouldProcessTouchInput else {
            inputCounters.ignoredTouches += touches.count
            for touch in touches where touch.phase != .moved {
                logInputEvent("ignored touch \(touch.phase.rawValue) id=\(touch.id) transport=\(activeTransport)")
            }
            return
        }

        if let touch = touches.first(where: { $0.phase == .began || $0.phase == .moved }) {
            if touchDevice.shouldReleasePenBeforeTouchInput {
                try releasePenBeforeTouch(timestamp: touch.timestamp, reason: "touch \(touch.phase.rawValue)")
            }
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
            let releasedPen = try device.release(timestamp: 0)
            try touchDevice.release(timestamp: 0)
            try padDevice.release()
            if releasedPen {
                Thread.sleep(forTimeInterval: inputSettleDelay)
                logStateRepair("released active pen before pad \(action.rawValue)")
            }

        case .panBegan:
            try touchDevice.release(timestamp: 0)
            try padDevice.release()
            let releasedPen = try device.releaseIfStale(minimumAge: stalePenReleaseMinimumAge, timestamp: 0)
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
            "session input summary samples=\(inputCounters.samples) touches=\(inputCounters.touches) ignoredTouches=\(inputCounters.ignoredTouches) gestures=\(inputCounters.gestures) pads=\(inputCounters.pads) tools=\(inputCounters.tools) cancels=\(inputCounters.cancels)"
        )
        sampleTiming.logSummary(transport: activeTransport)
    }

}

private struct InputCounters {
    var samples = 0
    var touches = 0
    var gestures = 0
    var pads = 0
    var tools = 0
    var cancels = 0
    var ignoredTouches = 0

    var hasInput: Bool {
        samples + touches + gestures + pads + tools + cancels + ignoredTouches > 0
    }
}

private struct PenSampleTimingDiagnostics {
    private static let gapThresholdNanoseconds: UInt64 = 25_000_000

    private var lastHostTimestamp: UInt64?
    private var lastSampleTimestamp: UInt64?
    private var strokeSampleCount = 0
    private var maxHostGap: UInt64 = 0
    private var maxSampleGap: UInt64 = 0
    private var totalHostGap: UInt64 = 0
    private var totalSampleGap: UInt64 = 0
    private var gapCount: UInt64 = 0
    private var largeGapCount: UInt64 = 0

    mutating func record(sample: PencilSample, mappedEvent: MappedPenEvent, transport: String) {
        let hostTimestamp = DispatchTime.now().uptimeNanoseconds

        if sample.phase == .began {
            strokeSampleCount = 0
            lastHostTimestamp = nil
            lastSampleTimestamp = nil
        }

        defer {
            lastHostTimestamp = hostTimestamp
            lastSampleTimestamp = sample.timestamp

            if sample.phase == .ended || sample.phase == .cancelled {
                strokeSampleCount = 0
            } else {
                strokeSampleCount += 1
            }
        }

        guard sample.phase == .moved, strokeSampleCount > 0 else { return }
        guard let previousHostTimestamp = lastHostTimestamp, let previousSampleTimestamp = lastSampleTimestamp else { return }

        let hostGap = hostTimestamp >= previousHostTimestamp ? hostTimestamp - previousHostTimestamp : 0
        let sampleGap = sample.timestamp >= previousSampleTimestamp ? sample.timestamp - previousSampleTimestamp : 0

        maxHostGap = max(maxHostGap, hostGap)
        maxSampleGap = max(maxSampleGap, sampleGap)
        totalHostGap &+= hostGap
        totalSampleGap &+= sampleGap
        gapCount &+= 1

        if hostGap >= Self.gapThresholdNanoseconds || sampleGap >= Self.gapThresholdNanoseconds {
            largeGapCount &+= 1
        }
    }

    func logSummary(transport: String) {
        guard gapCount > 0 else { return }
        ServerLog.info(
            "pen timing summary avgHost=\(Self.ms(totalHostGap / gapCount))ms maxHost=\(Self.ms(maxHostGap))ms avgSample=\(Self.ms(totalSampleGap / gapCount))ms maxSample=\(Self.ms(maxSampleGap))ms gaps=\(gapCount) largeGaps=\(largeGapCount) transport=\(transport)"
        )
    }

    private static func ms(_ nanoseconds: UInt64) -> String {
        String(format: "%.2f", Double(nanoseconds) / 1_000_000.0)
    }
}
