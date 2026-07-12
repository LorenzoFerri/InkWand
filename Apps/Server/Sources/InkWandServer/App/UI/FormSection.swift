import SwiftCrossUI

struct FormSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppLabel(title, style: .heading)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                content
                    .gtkStyleClass("card")

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gtkStyleClass("boxed-list")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow: View {
    let title: String
    let value: String
    let icon: ServerIcon?

    init(title: String, value: String, icon: ServerIcon? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                ThemedIcon(icon)
            }
            AppLabel(title)
            Spacer()
            AppLabel(value)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HeaderRow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        AppLabel(title, style: .caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateRow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        AppLabel(title, style: .secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
