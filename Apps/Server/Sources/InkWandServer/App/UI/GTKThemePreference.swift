import Foundation
import SwiftCrossUI

#if canImport(GtkBackend)
    import CGtk
    import Gtk
#endif

enum GTKThemePreference {
    #if canImport(GtkBackend)
        nonisolated(unsafe) private static var didConfigure = false

        static func configureIfPossible() {
            guard let settings = gtk_settings_get_default() else {
                return
            }

            guard !didConfigure else {
                return
            }

            didConfigure = true
            applyDarkPreferenceIfNeeded(to: Gtk.GObject(settings))
        }

        static func configureIfPossible(for widget: Gtk.Widget) {
            guard !didConfigure else {
                return
            }

            guard let settings = gtk_widget_get_settings(widget.widgetPointer) else {
                return
            }

            didConfigure = true
            applyDarkPreferenceIfNeeded(to: Gtk.GObject(settings))
        }

        private static func applyDarkPreferenceIfNeeded(to settings: Gtk.GObject) {
            guard prefersDarkTheme() else {
                return
            }

            settings.setProperty(
                named: "gtk-application-prefer-dark-theme",
                newValue: true
            )
        }
    #else
        static func configureIfPossible() {}
    #endif

    static var swiftUIColorScheme: ColorScheme {
        prefersDarkTheme() ? .dark : .light
    }

    private static func prefersDarkTheme() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if containsDark(environment["ADW_DEBUG_COLOR_SCHEME"])
            || containsDark(environment["GTK_THEME"])
        {
            return true
        }

        if let colorScheme = readGSettings(
            schema: "org.gnome.desktop.interface",
            key: "color-scheme"
        ), colorScheme.contains("dark") {
            return true
        }

        if let gtkTheme = readGSettings(
            schema: "org.gnome.desktop.interface",
            key: "gtk-theme"
        ), containsDark(gtkTheme) {
            return true
        }

        return false
    }

    private static func containsDark(_ value: String?) -> Bool {
        value?.localizedCaseInsensitiveContains("dark") == true
    }

    private static func readGSettings(schema: String, key: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gsettings", "get", schema, key]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        } catch {
            return nil
        }
    }
}

#if canImport(GtkBackend)
    extension View {
        func gtkApplyThemePreference() -> some View {
            inspect(.onCreate) { (widget: Gtk.Widget) in
                GTKThemePreference.configureIfPossible(for: widget)
            }
        }
    }
#else
    extension View {
        func gtkApplyThemePreference() -> some View {
            self
        }
    }
#endif
