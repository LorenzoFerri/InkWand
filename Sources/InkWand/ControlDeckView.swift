#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import InkWandCore

struct ControlDeckView: View {
    @ObservedObject var connection: TabletConnection
    @Binding var showsControls: Bool
    @Binding var controlsPosition: ControlsPosition
    @Binding var controlOrder: [ControlDeckItem]

    var body: some View {
        GeometryReader { proxy in
            let deckInset: CGFloat = 8
            let itemHeight = max(proxy.size.height - deckInset * 2, 64)
            let encoderRowHeight = max((itemHeight - 8) / 2, 26)
            let encoderWidth = max(encoderRowHeight * 8.2, 230)
            let contentWidth = proxy.size.width - deckInset * 2

            controlDeckItems(encoderWidth: encoderWidth, encoderRowHeight: encoderRowHeight, contentWidth: contentWidth)
                .frame(width: contentWidth, height: itemHeight)
                .padding(deckInset)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 82, maxHeight: .infinity)
        .background(ControlDeckBackground())
    }

    private func controlDeckItems(encoderWidth: CGFloat, encoderRowHeight: CGFloat, contentWidth: CGFloat) -> some View {
        let unitWidth = flexibleUnitWidth(encoderWidth: encoderWidth, contentWidth: contentWidth)

        return HStack(spacing: 10) {
            ForEach(Array(controlOrder.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    DeckDivider()
                }
                controlItem(item, encoderWidth: encoderWidth, encoderRowHeight: encoderRowHeight)
                    .frame(width: groupWidth(for: item, unitWidth: unitWidth, encoderWidth: encoderWidth))
            }

            DeckDivider()
            statusMenu
        }
    }

    @ViewBuilder
    private func controlItem(_ item: ControlDeckItem, encoderWidth: CGFloat, encoderRowHeight: CGFloat) -> some View {
        switch item {
        case .history:
            historyControls
        case .brush:
            brushSettingControls(encoderWidth: encoderWidth, encoderRowHeight: encoderRowHeight)
        case .tools:
            toolControls
        case .pressure:
            pressureReadout
        }
    }

    private func flexibleUnitWidth(encoderWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = 10
        let dividerWidth: CGFloat = 1
        let readoutWidth: CGFloat = 96
        let optionsWidth: CGFloat = 84
        let brushWidth = encoderWidth
        let dividerCount = CGFloat(controlOrder.count)
        let childCount = CGFloat(controlOrder.count + Int(dividerCount) + 1)
        let totalSpacing = max(childCount - 1, 0) * spacing
        let groupedButtonSpacing = controlOrder.reduce(CGFloat.zero) { total, item in
            switch item {
            case .history, .tools:
                return total + spacing
            case .brush, .pressure:
                return total
            }
        }

        let fixedWidth = controlOrder.reduce(optionsWidth + dividerCount * dividerWidth + totalSpacing + groupedButtonSpacing) { total, item in
            switch item {
            case .brush:
                return total + brushWidth
            case .pressure:
                return total + readoutWidth
            case .history, .tools:
                return total
            }
        }

        let flexibleUnits = controlOrder.reduce(CGFloat.zero) { total, item in
            switch item {
            case .history, .tools:
                return total + 2
            case .brush, .pressure:
                return total
            }
        }

        guard flexibleUnits > 0 else { return 0 }
        return max((contentWidth - fixedWidth) / flexibleUnits, 1)
    }

    private func groupWidth(for item: ControlDeckItem, unitWidth: CGFloat, encoderWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = 10
        let readoutWidth: CGFloat = 96

        switch item {
        case .history, .tools:
            return unitWidth * 2 + spacing
        case .brush:
            return encoderWidth
        case .pressure:
            return readoutWidth
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
        ControlOptionsPopoverButton(
            mode: $connection.mode,
            showsControls: $showsControls,
            controlsPosition: $controlsPosition,
            controlOrder: $controlOrder
        ) {
            StatusOptionsModule(
                color: statusColor,
                stateText: connection.state.rawValue,
                transport: connection.activeTransportLabel
            )
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
#endif
