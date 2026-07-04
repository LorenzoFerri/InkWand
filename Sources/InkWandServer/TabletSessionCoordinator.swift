#if os(Linux)
import Foundation
import InkWandCore

final class TabletSessionCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let mapper = TabletMapper()
    private let device: UInputPenDevice
    private let padDevice: UInputPadDevice
    private let verbose: Bool
    private var activeSessionID = UUID()
    private var activeTransport = "none"
    private var didReceiveHello = false
    private var activeTool: PencilTool?

    init(device: UInputPenDevice, padDevice: UInputPadDevice, verbose: Bool) {
        self.device = device
        self.padDevice = padDevice
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
        try? device.release()
        try? padDevice.release()
        device.destroy()
        padDevice.destroy()
    }

    private func beginSession(transport: String) -> UUID {
        lock.lock()
        defer { lock.unlock() }

        activeSessionID = UUID()
        activeTransport = transport
        didReceiveHello = false
        try? device.release()
        try? padDevice.release()
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

        try? device.release()
        try? padDevice.release()
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

            if sample.phase == .ended || sample.phase == .cancelled {
                try device.liftTouch(tool: sample.tool)
                activeTool = sample.tool

                if verbose {
                    ServerLog.info("sample \(sample.phase.rawValue) lift transport=\(activeTransport)")
                }
                return
            }

            if sample.phase == .began {
                if let activeTool, activeTool != sample.tool {
                    try device.release()
                }
                try device.liftTouch(tool: sample.tool)
                activeTool = sample.tool
            }

            let event = mapper.map(sample)
            try device.emit(event)

            if verbose {
                ServerLog.info("sample \(sample.phase.rawValue) tool=\(event.tool.rawValue) x=\(event.x) y=\(event.y) p=\(event.pressure) tx=\(event.tiltX) ty=\(event.tiltY) transport=\(activeTransport)")
            }

        case .cancel:
            try device.release()

        case let .tool(tool):
            guard didReceiveHello else {
                if verbose {
                    ServerLog.info("ignoring \(transport) tool before hello")
                }
                return
            }

            if activeTool != tool {
                try device.release()
            }
            try device.liftTouch(tool: tool)
            activeTool = tool

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

            try padDevice.emit(action)

            if verbose {
                ServerLog.info("pad \(action.rawValue) transport=\(activeTransport)")
            }
        }
    }
}
#endif
