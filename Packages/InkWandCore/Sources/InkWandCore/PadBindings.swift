import Foundation

public struct KeyStroke: Codable, Equatable, Sendable {
    public var keyCodes: [Int32]
    public var hold: Bool

    public init(keyCodes: [Int32], hold: Bool = false) {
        self.keyCodes = keyCodes
        self.hold = hold
    }
}

public struct PadBindingMap: Codable, Equatable, Sendable {
    public var bindings: [PadAction: KeyStroke]

    public init(bindings: [PadAction: KeyStroke]) {
        self.bindings = bindings
    }

    public func binding(for action: PadAction) -> KeyStroke {
        bindings[action] ?? Self.default.bindings[action]!
    }

    public func validating(allowedKeyCodes: ClosedRange<Int32>) throws -> PadBindingMap {
        for (_, stroke) in bindings {
            guard !stroke.keyCodes.isEmpty else {
                throw PadBindingError.emptyStroke
            }
            for keyCode in stroke.keyCodes where !allowedKeyCodes.contains(keyCode) {
                throw PadBindingError.unsupportedKeyCode(keyCode)
            }
        }
        return self
    }

    public static let `default` = PadBindingMap(bindings: [
        .undo: KeyStroke(keyCodes: [29, 44]),
        .redo: KeyStroke(keyCodes: [29, 42, 44]),
        .brushSmaller: KeyStroke(keyCodes: [26]),
        .brushLarger: KeyStroke(keyCodes: [27]),
        .opacityLower: KeyStroke(keyCodes: [23]),
        .opacityHigher: KeyStroke(keyCodes: [24]),
        .panBegan: KeyStroke(keyCodes: [57], hold: true),
        .panEnded: KeyStroke(keyCodes: [57], hold: true),
    ])
}

public enum PadBindingError: Error, Equatable {
    case emptyStroke
    case unsupportedKeyCode(Int32)
}

public final class PadBindingStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var map: PadBindingMap

    public init(url: URL) throws {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            map = try JSONDecoder().decode(PadBindingMap.self, from: data)
        } else {
            map = .default
        }
    }

    public func load() -> PadBindingMap {
        lock.withLock { map }
    }

    public func save(_ nextMap: PadBindingMap) throws {
        try lock.withLock {
            map = nextMap
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(nextMap).write(to: url, options: [.atomic])
        }
    }

    public func reset() throws {
        try save(.default)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
