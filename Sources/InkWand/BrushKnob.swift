#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

struct BrushKnob: View {
    var size: CGFloat = 62
    let onStep: (Int) -> Void
    @State private var rotation: Angle = .degrees(-35)
    @State private var lastAngle: Double?
    @State private var accumulatedDelta = 0.0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                knobBase(size: size)
                knobTicks(size: size)
                knobFace(size: size)
                knobIndicator(size: size)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        rotate(to: value.location, around: center)
                    }
                    .onEnded { _ in
                        lastAngle = nil
                        accumulatedDelta = 0
                    }
            )
        }
        .frame(width: size, height: size)
    }

    private func knobBase(size: CGFloat) -> some View {
        Circle()
            .knobGlass(tint: .black.opacity(0.22), radius: size / 2)
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
            )
            .overlay(
                Circle()
                    .strokeBorder(.black.opacity(0.30), lineWidth: 1.2)
                    .padding(2)
            )
            .shadow(color: .black.opacity(0.34), radius: 5, y: 2)
    }

    private func knobTicks(size: CGFloat) -> some View {
        ForEach(0..<24, id: \.self) { index in
            Capsule()
                .fill(index % 4 == 0 ? .white.opacity(0.28) : .white.opacity(0.09))
                .frame(width: 1.2, height: index % 4 == 0 ? 5.5 : 3)
                .offset(y: -size * 0.40)
                .rotationEffect(.degrees(Double(index) * 15))
        }
    }

    private func knobFace(size: CGFloat) -> some View {
        Circle()
            .knobGlass(tint: .cyan.opacity(0.06), radius: size * 0.34)
            .frame(width: size * 0.68, height: size * 0.68)
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.13), lineWidth: 0.7)
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .blur(radius: 6)
                    .offset(x: size * 0.12, y: size * 0.12)
            }
    }

    private func knobIndicator(size: CGFloat) -> some View {
        Circle()
            .fill(.cyan.opacity(0.9))
            .frame(width: 5, height: 5)
            .shadow(color: .cyan.opacity(0.6), radius: 4)
            .offset(y: -size * 0.27)
            .rotationEffect(rotation)
    }

    private func rotate(to point: CGPoint, around center: CGPoint) {
        let angle = Self.angle(for: point, center: center)
        if let lastAngle {
            let delta = Self.shortestDelta(from: lastAngle, to: angle)
            accumulatedDelta += delta
            rotation = .degrees(rotation.degrees + delta)

            while accumulatedDelta >= 22 {
                accumulatedDelta -= 22
                onStep(1)
            }

            while accumulatedDelta <= -22 {
                accumulatedDelta += 22
                onStep(-1)
            }
        }
        lastAngle = angle
    }

    private static func angle(for point: CGPoint, center: CGPoint) -> Double {
        atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    }

    private static func shortestDelta(from start: Double, to end: Double) -> Double {
        var delta = end - start
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return delta
    }
}

private extension View {
    func knobGlass(tint: Color, radius: CGFloat) -> some View {
        modifier(KnobGlassSurface(tint: tint, radius: radius))
    }
}

private struct KnobGlassSurface: ViewModifier {
    let tint: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .foregroundStyle(.clear)
                .glassEffect(
                    .regular.tint(tint),
                    in: .rect(cornerRadius: radius)
                )
        } else {
            content
                .foregroundStyle(.clear)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().fill(tint))
        }
    }
}
#endif
