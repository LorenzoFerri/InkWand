import Foundation

public struct MappedPenEvent: Equatable, Sendable {
    public var x: Int32
    public var y: Int32
    public var pressure: Int32
    public var tiltX: Int32
    public var tiltY: Int32
    public var tool: PencilTool
    public var isTouching: Bool
    public var isToolPresent: Bool
    public var timestamp: UInt64

    public init(
        x: Int32,
        y: Int32,
        pressure: Int32,
        tiltX: Int32 = 0,
        tiltY: Int32 = 0,
        tool: PencilTool = .pen,
        isTouching: Bool,
        isToolPresent: Bool,
        timestamp: UInt64 = 0
    ) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.tool = tool
        self.isTouching = isTouching
        self.isToolPresent = isToolPresent
        self.timestamp = timestamp
    }
}

public struct TabletMapper: Sendable {
    public var maxX: Int32
    public var maxY: Int32
    public var maxPressure: Int32

    public init(maxX: Int32 = 65535, maxY: Int32 = 65535, maxPressure: Int32 = 65535) {
        self.maxX = maxX
        self.maxY = maxY
        self.maxPressure = maxPressure
    }

    public func map(_ sample: PencilSample) -> MappedPenEvent {
        let clampedX = clamp(sample.x, lower: 0, upper: 1)
        let clampedY = clamp(sample.y, lower: 0, upper: 1)
        let touching = sample.phase == .began || sample.phase == .moved
        let clampedPressure = touching ? clamp(sample.pressure, lower: 0, upper: 1) : 0
        let tilt = Self.makeTilt(altitude: sample.altitude, azimuth: sample.azimuth)

        return MappedPenEvent(
            x: Int32((clampedX * Double(maxX)).rounded()),
            y: Int32((clampedY * Double(maxY)).rounded()),
            pressure: Int32((clampedPressure * Double(maxPressure)).rounded()),
            tiltX: tilt.x,
            tiltY: tilt.y,
            tool: sample.tool,
            isTouching: touching,
            isToolPresent: touching,
            timestamp: sample.timestamp
        )
    }

    public static func makeTilt(altitude: Double?, azimuth: Double?) -> (x: Int32, y: Int32) {
        guard let altitude, let azimuth else {
            return (0, 0)
        }

        let altitudeDegrees = altitude * 180.0 / .pi
        let tiltMagnitude = clampStatic(90.0 - altitudeDegrees, lower: 0, upper: 90)
        let tiltX = tiltMagnitude * cos(azimuth)
        let tiltY = tiltMagnitude * sin(azimuth)

        return (
            Int32(clampStatic(tiltX.rounded(), lower: -90, upper: 90)),
            Int32(clampStatic(tiltY.rounded(), lower: -90, upper: 90))
        )
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        Self.clampStatic(value, lower: lower, upper: upper)
    }

    private static func clampStatic(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
