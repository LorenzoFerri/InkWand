#if canImport(UIKit)
import UIKit
import InkWandCore

final class PencilSurfaceView: UIView, UIPencilInteractionDelegate {
    weak var connection: TabletConnection?
    var controlsPosition: ControlsPosition = .top {
        didSet {
            guard controlsPosition != oldValue else { return }
            setNeedsLayout()
        }
    }
    var reservesControlDeckSpace = true {
        didSet {
            guard reservesControlDeckSpace != oldValue else { return }
            setNeedsLayout()
        }
    }
    private let activeAreaLayer = CAShapeLayer()
    private let dotGridLayer = CAShapeLayer()
    private let trailContainerLayer = CALayer()
    private var currentTrailLayer: CAShapeLayer?
    private var currentTrailPath: UIBezierPath?
    private var hasActiveStroke = false
    private let outerPadding: CGFloat = 16
    private let controlDeckReservedHeight: CGFloat = 92

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .black
        isMultipleTouchEnabled = true
        isOpaque = true

        activeAreaLayer.fillColor = UIColor(white: 0.10, alpha: 1.0).cgColor
        activeAreaLayer.strokeColor = UIColor(white: 0.18, alpha: 1.0).cgColor
        activeAreaLayer.lineWidth = 1
        layer.addSublayer(activeAreaLayer)

        dotGridLayer.fillColor = UIColor(white: 0.55, alpha: 0.22).cgColor
        layer.addSublayer(dotGridLayer)

        trailContainerLayer.masksToBounds = true
        layer.addSublayer(trailContainerLayer)

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        addInteraction(pencilInteraction)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        activeAreaLayer.path = UIBezierPath(roundedRect: activeArea, cornerRadius: 18).cgPath
        dotGridLayer.frame = activeArea
        dotGridLayer.path = dotGridPath(in: activeArea.size).cgPath
        trailContainerLayer.frame = activeArea
        trailContainerLayer.cornerRadius = 18
        connection?.updateCanvasSize(activeArea.size)
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        connection?.toggleTool()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        send(touches, phase: .began, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touch.type == .pencil {
            let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
            send(coalesced, phase: .moved)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        send(touches, phase: .ended, event: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        send(touches, phase: .cancelled, event: event)
    }

    private func send(_ touches: Set<UITouch>, phase: PencilPhase, event: UIEvent?) {
        for touch in touches where touch.type == .pencil {
            let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
            send(coalesced, phase: phase)
        }
    }

    private func send(_ touches: [UITouch], phase: PencilPhase) {
        let activeArea = activeArea
        guard activeArea.width > 0, activeArea.height > 0 else { return }
        let tool = connection?.tool ?? .pen

        for touch in touches where touch.type == .pencil {
            let point = touch.location(in: self)
            let isInsideActiveArea = activeArea.contains(point)

            if phase == .began {
                guard isInsideActiveArea else { continue }
                hasActiveStroke = true
            } else {
                guard hasActiveStroke else { continue }
            }

            if !isInsideActiveArea, phase == .moved {
                continue
            }

            let maxForce = touch.maximumPossibleForce > 0 ? touch.maximumPossibleForce : 1
            let isReleasing = phase == .ended || phase == .cancelled
            let pressure = isReleasing ? 0 : (touch.force > 0 ? touch.force / maxForce : 0)
            let azimuth = touch.azimuthAngle(in: self)
            let clampedPoint = CGPoint(
                x: min(max(point.x, activeArea.minX), activeArea.maxX),
                y: min(max(point.y, activeArea.minY), activeArea.maxY)
            )
            let localPoint = CGPoint(x: clampedPoint.x - activeArea.minX, y: clampedPoint.y - activeArea.minY)

            updateTrail(at: localPoint, phase: phase, pressure: pressure)

            connection?.send(
                PencilSample(
                    phase: phase,
                    tool: tool,
                    x: Double((clampedPoint.x - activeArea.minX) / activeArea.width),
                    y: Double((clampedPoint.y - activeArea.minY) / activeArea.height),
                    pressure: Double(pressure),
                    timestamp: Self.nanoseconds(from: touch.timestamp),
                    altitude: Double(touch.altitudeAngle),
                    azimuth: Double(azimuth)
                )
            )

            if phase == .ended || phase == .cancelled {
                hasActiveStroke = false
                finishTrail()
            }
        }
    }

    private func dotGridPath(in size: CGSize) -> UIBezierPath {
        let path = UIBezierPath()
        let spacing: CGFloat = 24
        let radius: CGFloat = 1.15
        let minimumEdgeMargin: CGFloat = 34

        let usableWidth = max(size.width - minimumEdgeMargin * 2, 0)
        let usableHeight = max(size.height - minimumEdgeMargin * 2, 0)
        let columnCount = max(Int(floor(usableWidth / spacing)) + 1, 1)
        let rowCount = max(Int(floor(usableHeight / spacing)) + 1, 1)
        let horizontalInset = (size.width - CGFloat(columnCount - 1) * spacing) / 2
        let verticalInset = (size.height - CGFloat(rowCount - 1) * spacing) / 2

        for row in 0..<rowCount {
            let y = verticalInset + CGFloat(row) * spacing
            for column in 0..<columnCount {
                let x = horizontalInset + CGFloat(column) * spacing
                path.append(
                    UIBezierPath(
                        ovalIn: CGRect(
                            x: x - radius,
                            y: y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                    )
                )
            }
        }

        return path
    }

    private static func nanoseconds(from timestamp: TimeInterval) -> UInt64 {
        UInt64(max(timestamp, 0) * 1_000_000_000)
    }

    private func updateTrail(at point: CGPoint, phase: PencilPhase, pressure: CGFloat) {
        switch phase {
        case .began:
            beginTrail(at: point, pressure: pressure)
        case .moved:
            appendTrailPoint(point, pressure: pressure)
        case .ended, .cancelled:
            appendTrailPoint(point, pressure: pressure)
        }
    }

    private func beginTrail(at point: CGPoint, pressure: CGFloat) {
        finishTrail()

        let path = UIBezierPath()
        path.move(to: point)

        let shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor.white.withAlphaComponent(0.88).cgColor
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        shapeLayer.lineWidth = trailWidth(for: pressure)
        shapeLayer.path = path.cgPath
        shapeLayer.shadowColor = UIColor.systemTeal.cgColor
        shapeLayer.shadowOpacity = 0.45
        shapeLayer.shadowRadius = 5
        shapeLayer.shadowOffset = .zero

        trailContainerLayer.addSublayer(shapeLayer)
        currentTrailPath = path
        currentTrailLayer = shapeLayer
    }

    private func appendTrailPoint(_ point: CGPoint, pressure: CGFloat) {
        guard let currentTrailPath, let currentTrailLayer else {
            beginTrail(at: point, pressure: pressure)
            return
        }

        currentTrailPath.addLine(to: point)
        currentTrailLayer.path = currentTrailPath.cgPath
        currentTrailLayer.lineWidth = trailWidth(for: pressure)
    }

    private func finishTrail() {
        guard let layer = currentTrailLayer else { return }

        currentTrailLayer = nil
        currentTrailPath = nil

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = 0
        fade.duration = 0.75
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = 0
        layer.add(fade, forKey: "inkwand.trail.fade")

        DispatchQueue.main.asyncAfter(deadline: .now() + fade.duration) { [weak layer] in
            layer?.removeFromSuperlayer()
        }
    }

    private func trailWidth(for pressure: CGFloat) -> CGFloat {
        2.5 + min(max(pressure, 0), 1) * 4.5
    }

    private var activeArea: CGRect {
        let targetAspect = 16.0 / 9.0
        let availableBounds = bounds.insetBy(dx: outerPadding, dy: outerPadding)
        guard availableBounds.width > 0, availableBounds.height > 0 else { return .zero }

        let controlSafeInset = switch controlsPosition {
        case .top:
            safeAreaInsets.top
        case .bottom:
            safeAreaInsets.bottom
        }
        let reservedControls = reservesControlDeckSpace ? min(controlDeckReservedHeight + controlSafeInset, availableBounds.height * 0.30) : 0
        let reservedInsets: UIEdgeInsets = switch controlsPosition {
        case .top:
            UIEdgeInsets(top: reservedControls, left: 0, bottom: 0, right: 0)
        case .bottom:
            UIEdgeInsets(top: 0, left: 0, bottom: reservedControls, right: 0)
        }
        let tabletBounds = availableBounds.inset(
            by: reservedInsets
        )
        guard tabletBounds.width > 0, tabletBounds.height > 0 else { return .zero }

        let currentAspect = tabletBounds.width / tabletBounds.height
        if currentAspect < targetAspect {
            let height = tabletBounds.width / targetAspect
            let y = switch controlsPosition {
            case .top:
                tabletBounds.minY
            case .bottom:
                tabletBounds.maxY - height
            }

            return CGRect(
                x: tabletBounds.minX,
                y: y,
                width: tabletBounds.width,
                height: height
            )
        }

        let width = tabletBounds.height * targetAspect
        return CGRect(
            x: tabletBounds.minX + (tabletBounds.width - width) / 2.0,
            y: tabletBounds.minY,
            width: width,
            height: tabletBounds.height
        )
    }
}
#endif
