import SwiftCrossUI

#if canImport(GtkBackend)
    import Gtk
#endif

enum GTKApplicationStyle {
    static let css = """
    .card {
        background-color: var(--card-bg-color);
        color: var(--card-fg-color);
        border-radius: 12px;
    }

    .view {
        background-color: var(--view-bg-color);
        color: var(--view-fg-color);
        border: none;
        outline: none;
    }

    .sidebar {
        background-color: var(--sidebar-bg-color);
        color: var(--sidebar-fg-color);
        border: none;
        outline: none;
    }

    .navigation-sidebar > row:selected {
        background-color: color-mix(in oklab, var(--view-fg-color), transparent 90%);
    }

    .navigation-sidebar > row:hover {
        background-color: color-mix(in oklab, var(--view-fg-color), transparent 80%);
    }

    .navigation-sidebar > row {
        margin-bottom: 4px !important;
        border-radius: 12px;
    }
    """
}

extension View {
    func gtkApplyApplicationStyle() -> some View {
        #if canImport(GtkBackend)
            inspect(.onCreate) { (_: Gtk.Widget) in
                GTKApplicationStyleLoader.apply()
            }
        #else
            self
        #endif
    }
}

#if canImport(GtkBackend)
    @MainActor
    private enum GTKApplicationStyleLoader {
        private static var provider: Gtk.CSSProvider?

        static func apply() {
            if provider == nil {
                provider = Gtk.CSSProvider()
            }
            provider?.loadCss(from: GTKApplicationStyle.css)
        }
    }
#endif
