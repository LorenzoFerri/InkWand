#if canImport(SwiftUI)
import SwiftUI

enum RelativeInputEvent {
    case increment
    case decrement
}

struct HorizontalRelativeInputControl: View {
    var width: CGFloat = 128
    var height: CGFloat = 28
    var stepDistance: CGFloat = 18
    var title: String = ""
    var accessibilityLabel: String = "Relative input"
    var accessibilityHint: String = "Drag horizontally to adjust."
    let onEvent: (RelativeInputEvent) -> Void

    @State private var residualDrag: CGFloat = 0
    @State private var lastDragTranslation: CGFloat = 0
    @State private var tickPhase: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cornerRadius = min(size.height / 2, 18)
            let tickSpacing = max(stepDistance, 12)
            let labelWidth = min(max(size.width * 0.26, 68), 84)
            let trackWidth = max(size.width - labelWidth - 10, 44)

            ZStack {
                wheelBase(cornerRadius: cornerRadius)

                HStack(spacing: 4) {
                    labelContent
                        .padding(.leading, 8)
                        .frame(width: labelWidth, alignment: .leading)

                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1, height: max(size.height - 14, 8))

                    ZStack {
                        tickTexture(size: CGSize(width: trackWidth, height: size.height), tickSpacing: tickSpacing)
                        centerGuide(size: CGSize(width: trackWidth, height: size.height))
                        stepIndicators
                    }
                    .frame(width: trackWidth, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(isDragging ? 1.018 : 1)
            .animation(.bouncy(duration: 0.22, extraBounce: 0.28), value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragChanged(value, tickSpacing: tickSpacing)
                    }
                    .onEnded { _ in
                        dragEnded()
                    }
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
        }
        .frame(width: width, height: height)
    }

    private var labelContent: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .accessibilityHidden(true)
    }

    private func wheelBase(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(
                isDragging ? .regular.tint(.cyan.opacity(0.12)).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
            .animation(.snappy(duration: 0.12), value: isDragging)
    }

    private func tickTexture(size: CGSize, tickSpacing: CGFloat) -> some View {
        let patternPeriod = tickSpacing * 3
        let tickCount = max(Int(ceil((size.width + patternPeriod * 2) / tickSpacing)), 12)
        let baseOffset = wrappedPhase(tickPhase, period: patternPeriod) - patternPeriod

        return ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let isMajor = index % 3 == 0

                Capsule()
                    .fill(isMajor ? .white.opacity(0.24) : .white.opacity(0.10))
                    .frame(width: isMajor ? 1.3 : 0.8, height: isMajor ? size.height * 0.46 : size.height * 0.26)
                    .position(
                        x: baseOffset + CGFloat(index) * tickSpacing,
                        y: size.height / 2
                    )
            }
        }
    }

    private func centerGuide(size: CGSize) -> some View {
        Capsule()
            .fill(.cyan.opacity(isDragging ? 0.92 : 0.76))
            .frame(width: 1.6, height: size.height * 0.48)
            .shadow(color: .cyan.opacity(isDragging ? 0.26 : 0.12), radius: 2)
            .animation(.snappy(duration: 0.12), value: isDragging)
    }

    private var stepIndicators: some View {
        HStack {
            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.horizontal, 8)
    }

    private func dragChanged(_ value: DragGesture.Value, tickSpacing: CGFloat) {
        isDragging = true

        let delta = value.translation.width - lastDragTranslation
        lastDragTranslation = value.translation.width
        residualDrag += delta
        tickPhase += delta

        while residualDrag >= stepDistance {
            residualDrag -= stepDistance
            emit(.increment)
        }

        while residualDrag <= -stepDistance {
            residualDrag += stepDistance
            emit(.decrement)
        }

        tickPhase = wrappedPhase(tickPhase, period: tickSpacing * 3)
    }

    private func dragEnded() {
        isDragging = false
        residualDrag = 0
        lastDragTranslation = 0
    }

    private func emit(_ event: RelativeInputEvent) {
        onEvent(event)
    }

    private func wrappedPhase(_ value: CGFloat, period: CGFloat) -> CGFloat {
        guard period > 0 else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: period)
        return remainder >= 0 ? remainder : remainder + period
    }
}

#endif
