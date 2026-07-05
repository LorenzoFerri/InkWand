#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import InkWandCore

struct ControlDeckView: View {
    @ObservedObject var connection: TabletConnection
    @Binding var showsControls: Bool
    @Binding var controlsPosition: ControlsPosition
    @Binding var controlOrder: [ControlDeckItem]
    @State private var isPanPressed = false
    @State private var brushStepDirection = 0

    var body: some View {
        GeometryReader { proxy in
            let deckInset: CGFloat = 8
            let itemHeight = max(proxy.size.height - deckInset * 2, 64)
            let knobSize = max(itemHeight - 18, 52)
            let contentWidth = proxy.size.width - deckInset * 2

            controlDeckItems(knobSize: knobSize, contentWidth: contentWidth)
                .frame(width: contentWidth, height: itemHeight)
                .padding(deckInset)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 82, maxHeight: .infinity)
        .background(ControlDeckBackground())
    }

    private func controlDeckItems(knobSize: CGFloat, contentWidth: CGFloat) -> some View {
        let unitWidth = flexibleUnitWidth(knobSize: knobSize, contentWidth: contentWidth)

        return HStack(spacing: 10) {
            ForEach(Array(controlOrder.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    DeckDivider()
                }
                controlItem(item, knobSize: knobSize)
                    .frame(width: groupWidth(for: item, unitWidth: unitWidth, knobSize: knobSize))
            }

            DeckDivider()
            statusMenu
        }
    }

    @ViewBuilder
    private func controlItem(_ item: ControlDeckItem, knobSize: CGFloat) -> some View {
        switch item {
        case .history:
            historyControls
        case .brush:
            brushControls(knobSize: knobSize)
        case .tools:
            toolControls
        case .pan:
            PadHoldButton(systemName: "hand.raised", label: "PAN", isPressed: $isPanPressed) { pressed in
                connection.sendPadAction(pressed ? .panBegan : .panEnded)
            }
        case .pressure:
            pressureReadout
        }
    }

    private func flexibleUnitWidth(knobSize: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = 10
        let dividerWidth: CGFloat = 1
        let readoutWidth: CGFloat = 96
        let optionsWidth: CGFloat = 84
        let brushWidth = knobSize + spacing + readoutWidth
        let dividerCount = CGFloat(controlOrder.count)
        let childCount = CGFloat(controlOrder.count + Int(dividerCount) + 1)
        let totalSpacing = max(childCount - 1, 0) * spacing
        let groupedButtonSpacing = controlOrder.reduce(CGFloat.zero) { total, item in
            switch item {
            case .history, .tools:
                return total + spacing
            case .brush, .pan, .pressure:
                return total
            }
        }

        let fixedWidth = controlOrder.reduce(optionsWidth + dividerCount * dividerWidth + totalSpacing + groupedButtonSpacing) { total, item in
            switch item {
            case .brush:
                return total + brushWidth
            case .pressure:
                return total + readoutWidth
            case .history, .tools, .pan:
                return total
            }
        }

        let flexibleUnits = controlOrder.reduce(CGFloat.zero) { total, item in
            switch item {
            case .history, .tools:
                return total + 2
            case .pan:
                return total + 1
            case .brush, .pressure:
                return total
            }
        }

        guard flexibleUnits > 0 else { return 0 }
        return max((contentWidth - fixedWidth) / flexibleUnits, 1)
    }

    private func groupWidth(for item: ControlDeckItem, unitWidth: CGFloat, knobSize: CGFloat) -> CGFloat {
        let spacing: CGFloat = 10
        let readoutWidth: CGFloat = 96

        switch item {
        case .history, .tools:
            return unitWidth * 2 + spacing
        case .pan:
            return unitWidth
        case .brush:
            return knobSize + spacing + readoutWidth
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

    private func brushControls(knobSize: CGFloat) -> some View {
        HStack(spacing: 10) {
            BrushKnob(size: knobSize) { direction in
                showBrushStep(direction)
                connection.sendPadAction(direction < 0 ? .brushSmaller : .brushLarger)
            }

            RelativeControlPanel(
                title: "BRUSH",
                value: brushStepText,
                footnote: "RELATIVE",
                direction: brushStepDirection
            )
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

    private var brushStepText: String {
        switch brushStepDirection {
        case let direction where direction > 0:
            return "+STEP"
        case let direction where direction < 0:
            return "-STEP"
        default:
            return "STEP"
        }
    }

    private var formattedTilt: String {
        "\(Int(connection.lastTiltDegrees.rounded()))°"
    }

    private func showBrushStep(_ direction: Int) {
        brushStepDirection = direction

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            if brushStepDirection == direction {
                brushStepDirection = 0
            }
        }
    }
}
#endif
