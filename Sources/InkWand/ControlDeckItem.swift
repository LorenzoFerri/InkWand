enum ControlDeckItem: String, CaseIterable, Identifiable {
    case history
    case brush
    case tools
    case pressure

    var id: String { rawValue }
}
