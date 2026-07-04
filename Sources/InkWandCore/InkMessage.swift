import Foundation

public enum PencilPhase: String, Codable, Sendable {
    case began
    case moved
    case ended
    case cancelled
}

public enum PencilTool: String, Codable, Sendable {
    case pen
    case eraser
}

public enum PadAction: String, Codable, Sendable {
    case undo
    case redo
    case brushSmaller
    case brushLarger
    case panBegan
    case panEnded
}

public struct TabletHello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var canvasWidth: Double
    public var canvasHeight: Double
    public var deviceName: String

    public init(protocolVersion: Int, canvasWidth: Double, canvasHeight: Double, deviceName: String) {
        self.protocolVersion = protocolVersion
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.deviceName = deviceName
    }
}

public struct PencilSample: Codable, Equatable, Sendable {
    public var phase: PencilPhase
    public var tool: PencilTool
    public var x: Double
    public var y: Double
    public var pressure: Double
    public var timestamp: UInt64
    public var altitude: Double?
    public var azimuth: Double?

    public init(
        phase: PencilPhase,
        tool: PencilTool = .pen,
        x: Double,
        y: Double,
        pressure: Double,
        timestamp: UInt64,
        altitude: Double? = nil,
        azimuth: Double? = nil
    ) {
        self.phase = phase
        self.tool = tool
        self.x = x
        self.y = y
        self.pressure = pressure
        self.timestamp = timestamp
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

extension PencilSample {
    private enum CodingKeys: String, CodingKey {
        case phase
        case tool
        case x
        case y
        case pressure
        case timestamp
        case altitude
        case azimuth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.phase = try container.decode(PencilPhase.self, forKey: .phase)
        self.tool = try container.decodeIfPresent(PencilTool.self, forKey: .tool) ?? .pen
        self.x = try container.decode(Double.self, forKey: .x)
        self.y = try container.decode(Double.self, forKey: .y)
        self.pressure = try container.decode(Double.self, forKey: .pressure)
        self.timestamp = try container.decode(UInt64.self, forKey: .timestamp)
        self.altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        self.azimuth = try container.decodeIfPresent(Double.self, forKey: .azimuth)
    }
}

public enum InkMessage: Equatable, Sendable {
    case hello(TabletHello)
    case sample(PencilSample)
    case tool(PencilTool)
    case pad(PadAction)
    case cancel
}

extension InkMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case hello
        case sample
        case tool
        case pad
        case cancel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(MessageType.self, forKey: .type) {
        case .hello:
            self = .hello(try container.decode(TabletHello.self, forKey: .payload))
        case .sample:
            self = .sample(try container.decode(PencilSample.self, forKey: .payload))
        case .tool:
            self = .tool(try container.decode(PencilTool.self, forKey: .payload))
        case .pad:
            self = .pad(try container.decode(PadAction.self, forKey: .payload))
        case .cancel:
            self = .cancel
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(hello):
            try container.encode(MessageType.hello, forKey: .type)
            try container.encode(hello, forKey: .payload)
        case let .sample(sample):
            try container.encode(MessageType.sample, forKey: .type)
            try container.encode(sample, forKey: .payload)
        case let .tool(tool):
            try container.encode(MessageType.tool, forKey: .type)
            try container.encode(tool, forKey: .payload)
        case let .pad(action):
            try container.encode(MessageType.pad, forKey: .type)
            try container.encode(action, forKey: .payload)
        case .cancel:
            try container.encode(MessageType.cancel, forKey: .type)
        }
    }
}

public enum JSONLineCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    public static func encode(_ message: InkMessage) throws -> Data {
        var data = try encoder.encode(message)
        data.append(0x0A)
        return data
    }

    public static func decodeLine(_ line: Data) throws -> InkMessage {
        let trimmed = line.dropLast(line.last == 0x0A ? 1 : 0)
        return try decoder.decode(InkMessage.self, from: Data(trimmed))
    }

    public static func decodeLine(_ line: String) throws -> InkMessage {
        try decoder.decode(InkMessage.self, from: Data(line.utf8))
    }
}
