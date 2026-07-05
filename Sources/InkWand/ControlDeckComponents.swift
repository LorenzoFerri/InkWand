import SwiftUI

enum ControlDeckMetrics {
    static let outerRadius: CGFloat = 24
    static let innerRadius: CGFloat = 16
    static let optionsButtonWidth: CGFloat = 84
}

struct PadButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: ControlDeckMetrics.innerRadius)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ToolPadButton: View {
    let systemName: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        button
            .buttonStyle(.plain)
    }

    private var button: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 20)

                Circle()
                    .fill(isActive ? .cyan.opacity(0.86) : .white.opacity(0.18))
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.72))
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
            .glassEffect(
                isActive
                    ? .regular.tint(.cyan.opacity(0.42)).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: ControlDeckMetrics.innerRadius)
            )
            .accessibilityLabel(label)
        }
    }
}

struct StatusOptionsModule: View {
    let color: Color
    let stateText: String
    let transport: String

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(height: 18)

                Text("OPTIONS")
                    .font(.system(size: 7, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Capsule()
                    .fill(.cyan.opacity(0.78))
                    .frame(width: 22, height: 2)
            }
            .foregroundStyle(.white.opacity(0.82))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .shadow(color: color.opacity(0.55), radius: 3)

                Text(transport)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            .frame(maxWidth: .infinity)
            .padding(.all, 8)
        }
        .frame(width: ControlDeckMetrics.optionsButtonWidth)
        .frame(minHeight: 64, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stateText), \(transport), options")
    }
}

struct ReadoutPanel: View {
    let title: String
    let value: String
    let footnote: String?
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.54))

            Text(value)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)

            if let footnote {
                Text(footnote)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }

            AccentMeter(progress: progress)
        }
        .frame(width: 76, alignment: .leading)
        .frame(minHeight: 64, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .glassEffect(
            .regular.tint(.black.opacity(0.4)),
            in: .rect(cornerRadius: ControlDeckMetrics.innerRadius)
        )
    }
}

struct ControlOptionsPanel: View {
    @Binding var mode: TabletConnectionMode
    @Binding var showsControls: Bool
    @Binding var controlsPosition: ControlsPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ControlOptionsRow(
                title: "Connection",
                subtitle: "Transport mode",
                systemName: "antenna.radiowaves.left.and.right"
            ) {
                Picker("Connection", selection: $mode) {
                    ForEach(TabletConnectionMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            ControlOptionsRow(
                title: "Controls",
                subtitle: showsControls ? "Visible" : "Hidden",
                systemName: showsControls ? "rectangle.topthird.inset.filled" : "rectangle.topthird.inset"
            ) {
                Toggle("Show Controls", isOn: $showsControls)
                    .labelsHidden()
            }

            ControlOptionsRow(
                title: "Position",
                subtitle: "Deck placement",
                systemName: "rectangle.3.group"
            ) {
                Picker("Position", selection: $controlsPosition) {
                    ForEach(ControlsPosition.allCases) { position in
                        Label(position.rawValue, systemImage: position.symbolName)
                            .tag(position)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
    }
}

struct ControlOptionsRow<Control: View>: View {
    let title: String
    let subtitle: String
    let systemName: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.86))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            control()
        }
        .frame(minHeight: 38)
    }
}

struct AccentMeter: View {
    let progress: Double

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)

        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.22))
            Capsule()
                .fill(.cyan.opacity(0.82))
                .frame(width: max(4, 58 * clampedProgress))
        }
        .frame(width: 58, height: 2)
    }
}

struct DeckDivider: View {
    let color: Color
    let width: CGFloat

    init(color: Color = .white.opacity(0.08), width: CGFloat = 0.5) {
        self.color = color
        self.width = width
    }

    var body: some View {
        color
            .frame(width: width)
    }
}
