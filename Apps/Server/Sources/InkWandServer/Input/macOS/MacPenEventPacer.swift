#if os(macOS)
import Dispatch
import Foundation
import InkWandCore

final class MacPenEventPacer: PenInputDevice, @unchecked Sendable {
    let keepsToolInProximityAfterLift: Bool
    var isTouchActive: Bool {
        stateLock.withLock { isTouching }
    }

    private enum Operation {
        case emit(MappedPenEvent)
        case release(UInt64)
        case switchTool(PencilTool, UInt64)
        case lift(PencilTool, UInt64)
        case releaseHover(UInt64)
        case destroy

        var timestamp: UInt64 {
            switch self {
            case let .emit(event):
                event.timestamp
            case let .release(timestamp),
                 let .switchTool(_, timestamp),
                 let .lift(_, timestamp),
                 let .releaseHover(timestamp):
                timestamp
            case .destroy:
                0
            }
        }
    }

    private struct PendingOperation {
        var operation: Operation
        var enqueueHostTime: UInt64
    }

    private let target: PenInputDevice
    private let queue = DispatchQueue(label: "app.inkwand.server.mac-pen-pacer", qos: .userInteractive)
    private let stateLock = NSLock()
    private var pending: [PendingOperation] = []
    private var timer: DispatchSourceTimer?
    private var lastEnqueueTime = DispatchTime.now().uptimeNanoseconds
    private var lastOutputHostTime: UInt64?
    private var lastOutputSampleTime: UInt64?
    private var latency = LatencySummary()
    private var isTouching = false
    private var activeTool: PencilTool?
    private var lastStateChange = Date.distantPast

    init(target: PenInputDevice) {
        self.target = target
        self.keepsToolInProximityAfterLift = target.keepsToolInProximityAfterLift
    }

    func emitDownOrMove(_ event: MappedPenEvent) throws {
        stateLock.withLock {
            isTouching = event.isTouching
            activeTool = event.tool
            lastStateChange = Date()
        }
        enqueue(.emit(event))
    }

    @discardableResult
    func release(timestamp: UInt64) throws -> Bool {
        stateLock.withLock {
            isTouching = false
            activeTool = nil
            lastStateChange = Date()
        }
        enqueue(.release(timestamp))
        return true
    }

    func switchTool(to tool: PencilTool, timestamp: UInt64) throws {
        stateLock.withLock {
            activeTool = tool
            lastStateChange = Date()
        }
        enqueue(.switchTool(tool, timestamp))
    }

    func releaseIfStale(minimumAge: TimeInterval, timestamp: UInt64) throws -> Bool {
        let shouldRelease = stateLock.withLock {
            (activeTool != nil || isTouching) && Date().timeIntervalSince(lastStateChange) >= minimumAge
        }
        guard shouldRelease else { return false }
        stateLock.withLock {
            activeTool = nil
            isTouching = false
            lastStateChange = Date()
        }
        enqueue(.releaseHover(timestamp))
        return true
    }

    func releaseHover(timestamp: UInt64) throws -> Bool {
        let shouldRelease = stateLock.withLock {
            activeTool != nil && !isTouching
        }
        guard shouldRelease else { return false }
        stateLock.withLock {
            activeTool = nil
            lastStateChange = Date()
        }
        enqueue(.releaseHover(timestamp))
        return true
    }

    func liftTouch(tool: PencilTool, timestamp: UInt64) throws {
        stateLock.withLock {
            isTouching = false
            activeTool = tool
            lastStateChange = Date()
        }
        enqueue(.lift(tool, timestamp))
    }

    func destroy() {
        enqueue(.destroy)
    }

    private func enqueue(_ operation: Operation) {
        queue.async {
            let now = DispatchTime.now().uptimeNanoseconds
            self.pending.append(PendingOperation(operation: operation, enqueueHostTime: now))
            self.lastEnqueueTime = now
            self.startTimerIfNeeded()
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .microseconds(1_000), leeway: .microseconds(150))
        timer.setEventHandler { [weak self] in
            self?.drainReadyOperations()
        }
        timer.resume()
        self.timer = timer
    }

    private func drainReadyOperations() {
        guard !pending.isEmpty else {
            timer?.cancel()
            timer = nil
            lastOutputHostTime = nil
            lastOutputSampleTime = nil
            return
        }

        var drained = 0
        while drained < Self.maximumOperationsPerTick, let pendingOperation = pending.first {
            let now = DispatchTime.now().uptimeNanoseconds
            guard isDue(pendingOperation.operation, now: now) else { return }
            pending.removeFirst()
            perform(pendingOperation.operation)
            latency.record(dispatchHostTime: now, enqueueHostTime: pendingOperation.enqueueHostTime)
            lastOutputHostTime = now
            lastOutputSampleTime = pendingOperation.operation.timestamp
            drained += 1
        }
    }

    private func isDue(_ operation: Operation, now: UInt64) -> Bool {
        guard let lastOutputHostTime, let lastOutputSampleTime else {
            return true
        }

        let sampleDelta = operation.timestamp >= lastOutputSampleTime ? operation.timestamp - lastOutputSampleTime : 0
        let desiredDelay = scaledDelay(forSampleDelta: sampleDelta)
        let elapsed = now >= lastOutputHostTime ? now - lastOutputHostTime : 0
        return elapsed >= desiredDelay
    }

    private func scaledDelay(forSampleDelta sampleDelta: UInt64) -> UInt64 {
        guard sampleDelta > 0 else { return 0 }
        guard let firstTimestamp = pending.first?.operation.timestamp,
              let lastTimestamp = pending.last?.operation.timestamp else {
            return min(sampleDelta, Self.maximumInterEventDelayNanoseconds)
        }

        let pendingSpan = lastTimestamp >= firstTimestamp ? lastTimestamp - firstTimestamp : 0
        guard pendingSpan > Self.maximumReplayDelayNanoseconds else {
            return min(sampleDelta, Self.maximumInterEventDelayNanoseconds)
        }

        let scale = Double(Self.maximumReplayDelayNanoseconds) / Double(pendingSpan)
        let compressed = UInt64(Double(sampleDelta) * scale)
        return min(max(compressed, Self.minimumInterEventDelayNanoseconds), Self.maximumInterEventDelayNanoseconds)
    }

    private func perform(_ operation: Operation) {
        do {
            switch operation {
            case let .emit(event):
                try target.emitDownOrMove(event)
            case let .release(timestamp):
                _ = try target.release(timestamp: timestamp)
            case let .switchTool(tool, timestamp):
                try target.switchTool(to: tool, timestamp: timestamp)
            case let .lift(tool, timestamp):
                try target.liftTouch(tool: tool, timestamp: timestamp)
            case let .releaseHover(timestamp):
                _ = try target.releaseHover(timestamp: timestamp)
            case .destroy:
                target.destroy()
            }
        } catch {
            ServerLog.info("macOS pen pacer dropped an operation: \(error)")
        }
    }

    private static let maximumReplayDelayNanoseconds: UInt64 = 35_000_000
    private static let minimumInterEventDelayNanoseconds: UInt64 = 500_000
    private static let maximumInterEventDelayNanoseconds: UInt64 = 4_000_000
    private static let maximumOperationsPerTick = 12
}

private struct LatencySummary {
    private var samples: [UInt64] = []
    private var lastLogHostTime = DispatchTime.now().uptimeNanoseconds

    mutating func record(dispatchHostTime: UInt64, enqueueHostTime: UInt64) {
        let latency = dispatchHostTime >= enqueueHostTime ? dispatchHostTime - enqueueHostTime : 0
        samples.append(latency)

        let shouldLogByCount = samples.count >= 1_000
        let shouldLogByTime = dispatchHostTime >= lastLogHostTime + 3_000_000_000
        guard shouldLogByCount || shouldLogByTime else { return }

        log(dispatchHostTime: dispatchHostTime)
    }

    private mutating func log(dispatchHostTime: UInt64) {
        guard !samples.isEmpty else { return }

        let sorted = samples.sorted()
        let total = samples.reduce(UInt64(0), &+)
        let avg = total / UInt64(samples.count)
        let p50 = percentile(sorted, 0.50)
        let p95 = percentile(sorted, 0.95)
        let max = sorted.last ?? 0

        ServerLog.info(
            "macOS pen pacer latency samples=\(samples.count) avg=\(Self.ms(avg))ms p50=\(Self.ms(p50))ms p95=\(Self.ms(p95))ms max=\(Self.ms(max))ms"
        )

        samples.removeAll(keepingCapacity: true)
        lastLogHostTime = dispatchHostTime
    }

    private func percentile(_ sorted: [UInt64], _ value: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * value)))
        return sorted[index]
    }

    private static func ms(_ nanoseconds: UInt64) -> String {
        String(format: "%.2f", Double(nanoseconds) / 1_000_000.0)
    }
}
#endif
