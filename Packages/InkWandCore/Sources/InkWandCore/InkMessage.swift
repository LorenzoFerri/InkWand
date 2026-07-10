import Foundation

public struct EncryptedMessage: Codable, Equatable, Sendable {
    public var nonce: String
    public var ciphertext: String
    public var tag: String

    public init(nonce: String, ciphertext: String, tag: String) {
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

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

public enum CanvasGesturePhase: String, Codable, Sendable {
    case began
    case moved
    case ended
    case cancelled
}

public enum TouchPhase: String, Codable, Sendable {
    case began
    case moved
    case ended
    case cancelled
}

public enum PadAction: String, Codable, Sendable {
    case undo
    case redo
    case brushSmaller
    case brushLarger
    case opacityLower
    case opacityHigher
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

public struct CanvasGesture: Codable, Equatable, Sendable {
    public var phase: CanvasGesturePhase
    public var x: Double
    public var y: Double
    public var translationX: Double
    public var translationY: Double
    public var scale: Double
    public var rotation: Double
    public var firstTouchX: Double
    public var firstTouchY: Double
    public var secondTouchX: Double
    public var secondTouchY: Double
    public var timestamp: UInt64

    public init(
        phase: CanvasGesturePhase,
        x: Double,
        y: Double,
        translationX: Double,
        translationY: Double,
        scale: Double,
        rotation: Double,
        firstTouchX: Double,
        firstTouchY: Double,
        secondTouchX: Double,
        secondTouchY: Double,
        timestamp: UInt64
    ) {
        self.phase = phase
        self.x = x
        self.y = y
        self.translationX = translationX
        self.translationY = translationY
        self.scale = scale
        self.rotation = rotation
        self.firstTouchX = firstTouchX
        self.firstTouchY = firstTouchY
        self.secondTouchX = secondTouchX
        self.secondTouchY = secondTouchY
        self.timestamp = timestamp
    }
}

extension CanvasGesture {
    private enum CodingKeys: String, CodingKey {
        case phase
        case x
        case y
        case translationX
        case translationY
        case scale
        case rotation
        case firstTouchX
        case firstTouchY
        case secondTouchX
        case secondTouchY
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(CanvasGesturePhase.self, forKey: .phase)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        translationX = try container.decode(Double.self, forKey: .translationX)
        translationY = try container.decode(Double.self, forKey: .translationY)
        scale = try container.decode(Double.self, forKey: .scale)
        rotation = try container.decode(Double.self, forKey: .rotation)
        firstTouchX = try container.decodeIfPresent(Double.self, forKey: .firstTouchX) ?? x
        firstTouchY = try container.decodeIfPresent(Double.self, forKey: .firstTouchY) ?? y
        secondTouchX = try container.decodeIfPresent(Double.self, forKey: .secondTouchX) ?? x
        secondTouchY = try container.decodeIfPresent(Double.self, forKey: .secondTouchY) ?? y
        timestamp = try container.decode(UInt64.self, forKey: .timestamp)
    }
}

public struct TouchSample: Codable, Equatable, Sendable {
    public var id: UInt64
    public var phase: TouchPhase
    public var x: Double
    public var y: Double
    public var pressure: Double
    public var width: Double
    public var height: Double
    public var timestamp: UInt64

    public init(
        id: UInt64,
        phase: TouchPhase,
        x: Double,
        y: Double,
        pressure: Double,
        width: Double,
        height: Double,
        timestamp: UInt64
    ) {
        self.id = id
        self.phase = phase
        self.x = x
        self.y = y
        self.pressure = pressure
        self.width = width
        self.height = height
        self.timestamp = timestamp
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
    case authRequest(AuthRequest)
    case authResponse(AuthResponse)
    case pairingRequest(PairingRequest)
    case pairingResponse(PairingResponse)
    case encrypted(EncryptedMessage)
    case hello(TabletHello)
    case sample(PencilSample)
    case tool(PencilTool)
    case pad(PadAction)
    case gesture(CanvasGesture)
    case touch(TouchSample)
    case touchFrame([TouchSample])
    case cancel
}

extension InkMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case authRequest
        case authResponse
        case pairingRequest
        case pairingResponse
        case encrypted
        case hello
        case sample
        case tool
        case pad
        case gesture
        case touch
        case touchFrame
        case cancel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(MessageType.self, forKey: .type) {
        case .authRequest:
            self = .authRequest(try container.decode(AuthRequest.self, forKey: .payload))
        case .authResponse:
            self = .authResponse(try container.decode(AuthResponse.self, forKey: .payload))
        case .pairingRequest:
            self = .pairingRequest(try container.decode(PairingRequest.self, forKey: .payload))
        case .pairingResponse:
            self = .pairingResponse(try container.decode(PairingResponse.self, forKey: .payload))
        case .encrypted:
            self = .encrypted(try container.decode(EncryptedMessage.self, forKey: .payload))
        case .hello:
            self = .hello(try container.decode(TabletHello.self, forKey: .payload))
        case .sample:
            self = .sample(try container.decode(PencilSample.self, forKey: .payload))
        case .tool:
            self = .tool(try container.decode(PencilTool.self, forKey: .payload))
        case .pad:
            self = .pad(try container.decode(PadAction.self, forKey: .payload))
        case .gesture:
            self = .gesture(try container.decode(CanvasGesture.self, forKey: .payload))
        case .touch:
            self = .touch(try container.decode(TouchSample.self, forKey: .payload))
        case .touchFrame:
            self = .touchFrame(try container.decode([TouchSample].self, forKey: .payload))
        case .cancel:
            self = .cancel
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .authRequest(request):
            try container.encode(MessageType.authRequest, forKey: .type)
            try container.encode(request, forKey: .payload)
        case let .authResponse(response):
            try container.encode(MessageType.authResponse, forKey: .type)
            try container.encode(response, forKey: .payload)
        case let .pairingRequest(request):
            try container.encode(MessageType.pairingRequest, forKey: .type)
            try container.encode(request, forKey: .payload)
        case let .pairingResponse(response):
            try container.encode(MessageType.pairingResponse, forKey: .type)
            try container.encode(response, forKey: .payload)
        case let .encrypted(message):
            try container.encode(MessageType.encrypted, forKey: .type)
            try container.encode(message, forKey: .payload)
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
        case let .gesture(gesture):
            try container.encode(MessageType.gesture, forKey: .type)
            try container.encode(gesture, forKey: .payload)
        case let .touch(touch):
            try container.encode(MessageType.touch, forKey: .type)
            try container.encode(touch, forKey: .payload)
        case let .touchFrame(touches):
            try container.encode(MessageType.touchFrame, forKey: .type)
            try container.encode(touches, forKey: .payload)
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
        var data = try encodePayload(message)
        data.append(0x0A)
        return data
    }

    public static func encodePayload(_ message: InkMessage) throws -> Data {
        try encoder.encode(message)
    }

    public static func decodePayload(_ data: Data) throws -> InkMessage {
        try decoder.decode(InkMessage.self, from: data)
    }

    public static func decodeLine(_ line: Data) throws -> InkMessage {
        let trimmed = line.dropLast(line.last == 0x0A ? 1 : 0)
        return try decodePayload(Data(trimmed))
    }

    public static func decodeLine(_ line: String) throws -> InkMessage {
        try decoder.decode(InkMessage.self, from: Data(line.utf8))
    }
}
