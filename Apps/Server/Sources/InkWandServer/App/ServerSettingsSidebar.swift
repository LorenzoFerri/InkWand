import SwiftCrossUI

struct ServerSettingsSidebar: View {
    @Binding var selectedSection: ServerSettingsSection?

    var body: some View {
        List(ServerSettingsSection.allCases, selection: $selectedSection) { section in
            SidebarItem(section: section)
        }
        .gtkStyleClass("navigation-sidebar")
    }
}

private struct SidebarItem: View {
    let section: ServerSettingsSection

    var body: some View {
        HStack(spacing: 10) {
            ThemedIcon(section.icon)
            AppLabel(section.title)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
