#if canImport(SwiftUI) && canImport(UIKit)
import Foundation

enum ControlDeckItem: String, CaseIterable, Identifiable {
    case history
    case brush
    case tools
    case pressure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history:
            return "Undo / Redo"
        case .brush:
            return "Brush"
        case .tools:
            return "Pen / Eraser"
        case .pressure:
            return "Pressure"
        }
    }

    var symbolName: String {
        switch self {
        case .history:
            return "arrow.uturn.backward.circle"
        case .brush:
            return "arrow.left.arrow.right.circle"
        case .tools:
            return "pencil.and.scribble"
        case .pressure:
            return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    static let defaultsKey = "InkWand.ControlDeckOrder"
    static let defaultOrder: [ControlDeckItem] = [.history, .brush, .tools, .pressure]

    static func loadOrder() -> [ControlDeckItem] {
        guard let storedValue = UserDefaults.standard.string(forKey: defaultsKey) else {
            return defaultOrder
        }

        let storedItems = storedValue.split(separator: ",").map(String.init)
        let decodedItems = storedItems.compactMap(ControlDeckItem.init(rawValue:))
        let hasUnknownItems = decodedItems.count != storedItems.count
        let hasAllGroups = Set(decodedItems) == Set(defaultOrder)

        guard !hasUnknownItems, hasAllGroups else {
            return defaultOrder
        }

        return decodedItems
    }

    static func saveOrder(_ order: [ControlDeckItem]) {
        let sanitizedOrder = order.filter { defaultOrder.contains($0) }
        UserDefaults.standard.set(
            sanitizedOrder.map(\.rawValue).joined(separator: ","),
            forKey: defaultsKey
        )
    }
}
#endif
