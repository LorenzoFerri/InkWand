import InkWandCore
import SwiftCrossUI

struct ServerSettingsView: View {
    let runtime: InkWandServerRuntime
    @Binding var autostartEnabled: Bool
    let refresh: () -> Void
    let setAutostart: (Bool) -> Void
    let openFirewall: @MainActor @Sendable () -> Void

    @State private var selectedSection: ServerSettingsSection? = .status

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ServerSettingsSidebar(selectedSection: $selectedSection)
                .frame(width: 280, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
                .gtkStyleClass("sidebar")

            Divider()

            ScrollView {
                ServerSettingsContentView(
                    selectedSection: selectedSection ?? .status,
                    runtime: runtime,
                    autostartEnabled: $autostartEnabled,
                    refresh: refresh,
                    setAutostart: setAutostart,
                    openFirewall: openFirewall
                )
                .padding(.horizontal, 32)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gtkStyleClass("view")
        }
        .gtkStyleClass("background")
        .colorScheme(GTKThemePreference.swiftUIColorScheme)
        .gtkApplyThemePreference()
    }
}

private struct ServerSettingsContentView: View {
    let selectedSection: ServerSettingsSection
    let runtime: InkWandServerRuntime
    @Binding var autostartEnabled: Bool
    let refresh: () -> Void
    let setAutostart: (Bool) -> Void
    let openFirewall: @MainActor @Sendable () -> Void

    var body: some View {
        switch selectedSection {
        case .status:
            VStack(alignment: .leading, spacing: 20) {
                StatusSection(state: runtime.state)
                ServerInfoSection(runtime: runtime)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .connections:
            ConnectionsSection(runtime: runtime, refresh: refresh)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .devices:
            VStack(alignment: .leading, spacing: 20) {
                TrustedDevicesSection(runtime: runtime, refresh: refresh)
                VirtualDevicesSection()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .settings:
            VStack(alignment: .leading, spacing: 20) {
                NetworkSection(port: Int(runtime.currentPort))
                StartupSection(
                    autostartEnabled: $autostartEnabled,
                    setAutostart: setAutostart,
                    openFirewall: openFirewall
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
