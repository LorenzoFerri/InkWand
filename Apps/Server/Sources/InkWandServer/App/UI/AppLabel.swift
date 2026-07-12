import SwiftCrossUI

struct AppLabel: View {
    enum Style {
        case body
        case heading
        case caption
        case secondary

        var font: Font {
            switch self {
            case .body:
                return .system(size: 15)
            case .heading:
                return .system(size: 18, weight: .bold)
            case .caption:
                return .system(size: 12)
            case .secondary:
                return .system(size: 13)
            }
        }

        var gtkClass: String {
            switch self {
            case .body:
                return ""
            case .heading:
                return "heading"
            case .caption, .secondary:
                return "dim-label"
            }
        }
    }

    let text: String
    let style: Style

    init(_ text: String, style: Style = .body) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(style.font)
            .gtkStyleClass(style.gtkClass)
    }
}
