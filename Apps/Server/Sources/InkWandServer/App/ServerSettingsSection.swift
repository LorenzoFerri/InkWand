enum ServerSettingsSection: CaseIterable, Identifiable {
    case status
    case connections
    case devices
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .status:
            return "Status"
        case .connections:
            return "Connections"
        case .devices:
            return "Devices"
        case .settings:
            return "Settings"
        }
    }

    var icon: ServerIcon {
        switch self {
        case .status:
            return .status
        case .connections:
            return .connections
        case .devices:
            return .devices
        case .settings:
            return .settings
        }
    }
}
