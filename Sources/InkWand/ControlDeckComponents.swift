#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

private enum ControlDeckMetrics {
    static let outerRadius: CGFloat = 24
    static let innerRadius: CGFloat = 16
    static let popoverWidth: CGFloat = 330
    static let optionsPopoverHeight: CGFloat = 548
    static let customizePopoverHeight: CGFloat = 486
}

struct ControlDeckBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ControlDeckMetrics.outerRadius, style: .continuous)
            .liquidGlassSurface(cornerRadius: ControlDeckMetrics.outerRadius, tint: .black.opacity(0.28))
    }
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
                .background(GlassKeyShape())
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
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.72))
                    .frame(height: 20)
                Capsule()
                    .fill(isActive ? .cyan.opacity(0.86) : .white.opacity(0.18))
                    .frame(width: 30, height: 2)
                Circle()
                    .fill(isActive ? .cyan.opacity(0.86) : .white.opacity(0.18))
                    .frame(width: 5, height: 5)
            }
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
            .background(GlassKeyShape(isActive: isActive))
            .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
    }
}

struct UtilityPadButton: View {
    let systemName: String
    let title: String
    var value: String?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(height: 18)
                Text(title)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                if let value {
                    Text(value)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Capsule()
                        .fill(.cyan.opacity(0.78))
                        .frame(width: 22, height: 2)
                }
            }
            .frame(width: 64)
            .frame(minHeight: 64, maxHeight: .infinity)
            .background(GlassKeyShape())
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(height: 18)

                Text("OPTIONS")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Capsule()
                    .fill(.cyan.opacity(0.78))
                    .frame(width: 22, height: 2)
            }
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
        }
        .frame(width: 68)
        .frame(minHeight: 64, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(GlassKeyShape())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stateText), \(transport), options")
    }
}

struct PadHoldButton: View {
    let systemName: String
    let label: String
    @Binding var isPressed: Bool
    let onPressChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isPressed ? .cyan.opacity(0.92) : .white.opacity(0.82))
                .frame(height: 20)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
            Circle()
                .fill(isPressed ? .cyan.opacity(0.86) : .white.opacity(0.18))
                .frame(width: 5, height: 5)
        }
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
        .background(GlassKeyShape(isActive: isPressed))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onPressChanged(true)
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    onPressChanged(false)
                }
        )
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
        .background(ReadoutBackground())
    }
}

struct RelativeControlPanel: View {
    let title: String
    let value: String
    let footnote: String
    let direction: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.54))
            Text(value)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(direction == 0 ? .white.opacity(0.82) : .cyan.opacity(0.9))
                .lineLimit(1)
            Text(footnote)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
            HStack(spacing: 4) {
                Capsule()
                    .fill(direction < 0 ? .cyan.opacity(0.86) : .white.opacity(0.20))
                Capsule()
                    .fill(direction == 0 ? .cyan.opacity(0.72) : .white.opacity(0.20))
                Capsule()
                    .fill(direction > 0 ? .cyan.opacity(0.86) : .white.opacity(0.20))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 2)
        }
        .frame(width: 76, alignment: .leading)
        .frame(minHeight: 64, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .background(ReadoutBackground())
    }
}

struct TelemetryTile: View {
    let systemName: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(height: 18)
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.54)
        }
        .frame(width: 64)
        .frame(minHeight: 64, maxHeight: .infinity)
        .background(GlassKeyShape())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}

struct StatusModule: View {
    let color: Color
    let stateText: String
    let transport: String
    let toolText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: 5)
                Text(stateText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(spacing: 5) {
                Text("\(transport) · \(toolText)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(width: 108, alignment: .leading)
        .frame(minHeight: 64, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .background(GlassKeyShape())
    }
}

struct ControlOptionsPopoverButton<Label: View>: View {
    @Binding var mode: TabletConnectionMode
    @Binding var showsControls: Bool
    @Binding var controlsPosition: ControlsPosition
    @Binding var controlOrder: [ControlDeckItem]
    @State private var showsPopover = false
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            ControlOptionsPopover(
                mode: $mode,
                showsControls: $showsControls,
                controlsPosition: $controlsPosition,
                controlOrder: $controlOrder
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct ControlOptionsPopover: View {
    @Binding var mode: TabletConnectionMode
    @Binding var showsControls: Bool
    @Binding var controlsPosition: ControlsPosition
    @Binding var controlOrder: [ControlDeckItem]

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Picker("Mode", selection: $mode) {
                        ForEach(TabletConnectionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }

                Section("Controls") {
                    Toggle("Show Controls", isOn: $showsControls)

                    Picker("Controls Position", selection: $controlsPosition) {
                        ForEach(ControlsPosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                }

                Section("Customize") {
                    NavigationLink {
                        ControlOrderEditor(controlOrder: $controlOrder)
                    } label: {
                        Label("Reorder Controls", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(width: ControlDeckMetrics.popoverWidth, height: ControlDeckMetrics.optionsPopoverHeight)
    }
}

struct ControlOrderEditor: View {
    @Binding var controlOrder: [ControlDeckItem]
    @State private var editMode: EditMode = .active

    var body: some View {
        Form {
            Section {
                ForEach(controlOrder) { item in
                    Label {
                        Text(item.title)
                    } icon: {
                        Image(systemName: item.symbolName)
                    }
                }
                .onMove(perform: move)
            } header: {
                Text("Drag controls to reorder the deck.")
            }

            Section {
                Button {
                    controlOrder = ControlDeckItem.defaultOrder
                    ControlDeckItem.saveOrder(controlOrder)
                } label: {
                    Label("Reset Order", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Reorder Controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func move(from source: IndexSet, to destination: Int) {
        withAnimation(.snappy(duration: 0.18)) {
            controlOrder.move(fromOffsets: source, toOffset: destination)
        }
        ControlDeckItem.saveOrder(controlOrder)
    }
}

struct HiddenControlsButton: View {
    var body: some View {
        Image(systemName: "slider.horizontal.3")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 48, height: 36)
            .background(
                Capsule()
                    .liquidGlassSurface(cornerRadius: 18, tint: .black.opacity(0.24))
            )
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

struct GlassKeyShape: View {
    var isActive = false

    var body: some View {
        RoundedRectangle(cornerRadius: ControlDeckMetrics.innerRadius, style: .continuous)
            .liquidGlassSurface(
                cornerRadius: ControlDeckMetrics.innerRadius,
                tint: isActive ? .cyan.opacity(0.20) : .black.opacity(0.18)
            )
    }
}

struct ReadoutBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ControlDeckMetrics.innerRadius, style: .continuous)
            .fill(.black.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: ControlDeckMetrics.innerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: ControlDeckMetrics.innerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.6)
                    .blendMode(.screen)
            }
    }
}

struct DeckDivider: View {
    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.13),
                        .white.opacity(0.05),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .frame(minHeight: 58, maxHeight: .infinity)
    }
}

private extension View {
    func liquidGlassSurface(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, tint: tint))
    }
}

private struct LiquidGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .foregroundStyle(.clear)
                .glassEffect(
                    .regular.tint(tint),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .foregroundStyle(.clear)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
#endif
