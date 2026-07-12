import SwiftCrossUI

#if canImport(GtkBackend)
    import CGtk
    import Gtk
    import GtkBackend
#endif

enum ServerIcon {
    case status
    case connections
    case devices
    case settings
    case ipad
    case usb
    case wifi
    case port
    case pen
    case touch
    case pad
    case firewall

    var gtkIconName: String {
        switch self {
        case .status:
            return "emblem-ok-symbolic"
        case .connections:
            return "network-workgroup-symbolic"
        case .devices, .ipad:
            return "input-tablet-symbolic"
        case .settings:
            return "preferences-system-symbolic"
        case .usb:
            return "drive-removable-media-symbolic"
        case .wifi:
            return "network-wireless-symbolic"
        case .port:
            return "network-server-symbolic"
        case .pen:
            return "input-tablet-symbolic"
        case .touch:
            return "input-touchpad-symbolic"
        case .pad:
            return "input-gaming-symbolic"
        case .firewall:
            return "security-high-symbolic"
        }
    }
}

#if canImport(GtkBackend)
    struct ThemedIcon: GtkWidgetRepresentable {
        let icon: ServerIcon
        let size: Int

        init(_ icon: ServerIcon, size: Int = 16) {
            self.icon = icon
            self.size = size
        }

        func makeGtkWidget(context _: Context) -> Gtk.Image {
            let image = Gtk.Image(iconName: icon.gtkIconName)
            image.pixelSize = size
            image.setSizeRequest(width: size, height: size)
            gtk_widget_add_css_class(image.widgetPointer, "lowres-icon")
            return image
        }

        func updateGtkWidget(_ gtkWidget: Gtk.Image, context _: Context) {
            gtkWidget.iconName = icon.gtkIconName
            gtkWidget.pixelSize = size
            gtkWidget.setSizeRequest(width: size, height: size)
            gtk_widget_add_css_class(gtkWidget.widgetPointer, "lowres-icon")
        }
    }
#else
    struct ThemedIcon: View {
        let icon: ServerIcon
        let size: Int

        init(_ icon: ServerIcon, size: Int = 16) {
            self.icon = icon
            self.size = size
        }

        var body: some View {
            Text("")
                .frame(width: size, height: size)
        }
    }
#endif
