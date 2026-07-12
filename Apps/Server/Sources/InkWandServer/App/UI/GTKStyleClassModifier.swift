import SwiftCrossUI

#if canImport(GtkBackend)
    import CGtk
    import Gtk
#endif

extension View {
    func gtkStyleClass(_ className: String) -> some View {
        #if canImport(GtkBackend)
            inspect(.onCreate) { (widget: Gtk.Widget) in
                guard !className.isEmpty else {
                    return
                }
                gtk_widget_add_css_class(widget.widgetPointer, className)
            }
        #else
            self
        #endif
    }
}
