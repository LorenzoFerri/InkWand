import SwiftUI
import InkWandCore

struct ControlDeckView: View {
    @ObservedObject var connection: TabletConnection
    @Binding var showsControls: Bool
    @Binding var controlsPosition: ControlsPosition
    @State private var showsOptions = false
    @State private var revealsControls = true
    @State private var controlsRevealTask: Task<Void, Never>?

    private let controlItems = ControlDeckItem.allCases

    var body: some View {
        GeometryReader { proxy in
            let deckInset: CGFloat = 8
            let itemHeight = max(proxy.size.height - deckInset * 2, 64)
            let encoderRowHeight = max((itemHeight - 8) / 2, 26)
            let encoderWidth = max(encoderRowHeight * 8.2, 230)
            let collapsedWidth: CGFloat = 84
            let contentWidth = max(proxy.size.width - deckInset * 2, 0)
            let deckWidth = showsControls ? proxy.size.width : collapsedWidth + deckInset * 2

            controlDeckItems(
                encoderWidth: encoderWidth,
                encoderRowHeight: encoderRowHeight
            )
            .frame(
                width: showsControls ? contentWidth : collapsedWidth,
                height: itemHeight,
                alignment: .trailing
            )
            .padding(deckInset)
            .frame(width: deckWidth, alignment: .trailing)
            .glassEffect(.regular, in: .rect(cornerRadius: ControlDeckMetrics.outerRadius))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(.snappy(duration: 0.22), value: showsControls)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 82, maxHeight: .infinity)
        .onAppear {
            revealsControls = showsControls
        }
        .onChange(of: showsControls) { _, isShowing in
            controlsRevealTask?.cancel()
            if isShowing {
                revealsControls = false
                controlsRevealTask = Task {
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.snappy(duration: 0.12)) {
                            revealsControls = true
                        }
                    }
                }
            } else {
                withAnimation(.snappy(duration: 0.10)) {
                    revealsControls = false
                }
            }
        }
    }

    private func controlDeckItems(
        encoderWidth: CGFloat,
        encoderRowHeight: CGFloat
    ) -> some View {
        HStack(spacing: 10) {
            if revealsControls {
                Group {
                    ForEach(Array(controlItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            DeckDivider()
                        }
                        controlItem(item, encoderWidth: encoderWidth, encoderRowHeight: encoderRowHeight)
                    }

                    DeckDivider()
                }
                .transition(.opacity)
            }
            statusMenu
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func controlItem(
        _ item: ControlDeckItem,
        encoderWidth: CGFloat,
        encoderRowHeight: CGFloat
    ) -> some View {
        switch item {
        case .history:
            historyControls
                .frame(minWidth: 98, maxWidth: .infinity)
        case .brush:
            brushSettingControls(encoderWidth: encoderWidth, encoderRowHeight: encoderRowHeight)
                .frame(width: encoderWidth)
                .layoutPriority(1)
        case .tools:
            toolControls
                .frame(minWidth: 98, maxWidth: .infinity)
        case .pressure:
            pressureReadout
                .frame(width: 96)
        }
    }

    private var historyControls: some View {
        HStack(spacing: 10) {
            PadButton(systemName: "arrow.uturn.backward") {
                connection.sendPadAction(.undo)
            }

            PadButton(systemName: "arrow.uturn.forward") {
                connection.sendPadAction(.redo)
            }
        }
    }

    private func brushSettingControls(encoderWidth: CGFloat, encoderRowHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            relativeInputRow(
                title: "Brush size",
                width: encoderWidth,
                height: encoderRowHeight,
                decrementAction: .brushSmaller,
                incrementAction: .brushLarger
            )

            relativeInputRow(
                title: "Opacity",
                width: encoderWidth,
                height: encoderRowHeight,
                decrementAction: .opacityLower,
                incrementAction: .opacityHigher
            )
        }
    }

    private func relativeInputRow(
        title: String,
        width: CGFloat,
        height: CGFloat,
        decrementAction: PadAction,
        incrementAction: PadAction
    ) -> some View {
        HorizontalRelativeInputControl(
            width: width,
            height: height,
            stepDistance: 18,
            title: title,
            accessibilityLabel: "\(title) encoder",
            accessibilityHint: "Drag right to increase. Drag left to decrease."
        ) { event in
            connection.sendPadAction(event == .decrement ? decrementAction : incrementAction)
        }
    }

    private var toolControls: some View {
        HStack(spacing: 10) {
            ToolPadButton(systemName: "pencil.tip", label: "PEN", isActive: connection.tool == .pen) {
                if connection.tool != .pen {
                    connection.setTool(.pen)
                }
            }

            ToolPadButton(systemName: "eraser", label: "ERASE", isActive: connection.tool == .eraser) {
                if connection.tool != .eraser {
                    connection.setTool(.eraser)
                }
            }
        }
    }

    private var pressureReadout: some View {
        ReadoutPanel(
            title: "PRESSURE",
            value: formattedPressure,
            footnote: "TILT \(formattedTilt)",
            progress: connection.lastPressure
        )
    }

    private var statusMenu: some View {
        Button {
            showsOptions.toggle()
        } label: {
            StatusOptionsModule(
                color: statusColor,
                stateText: connection.state.rawValue,
                transport: connection.activeTransportLabel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: ControlDeckMetrics.innerRadius))
        }
        .buttonStyle(.plain)
        .frame(width: ControlDeckMetrics.optionsButtonWidth)
        .layoutPriority(1.0)
        .popover(isPresented: $showsOptions, attachmentAnchor: .rect(.bounds), arrowEdge: controlsPosition == .top ? .top : .bottom) {
            ControlOptionsPanel(
                mode: $connection.mode,
                showsControls: $showsControls,
                controlsPosition: $controlsPosition
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var statusColor: Color {
        switch connection.state {
        case .connected:
            return .green
        case .connecting, .searching:
            return .yellow
        case .waiting:
            return .orange
        }
    }

    private var formattedPressure: String {
        "\(Int((connection.lastPressure * 100).rounded()))%"
    }

    private var formattedTilt: String {
        "\(Int(connection.lastTiltDegrees.rounded()))°"
    }
}
