#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

enum ControlsPosition: String, CaseIterable, Identifiable {
    case top = "Top"
    case bottom = "Bottom"

    var id: String { rawValue }

    var alignment: Alignment {
        switch self {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
}
#endif
