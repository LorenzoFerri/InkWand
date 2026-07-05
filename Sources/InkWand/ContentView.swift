import SwiftUI

struct ContentView: View {
    @StateObject private var connection = TabletConnection()
    @State private var showsControls = true
    @State private var controlsPosition: ControlsPosition = .top

    private let minimumControlsHeight: CGFloat = 82
    private let drawingOuterPadding: CGFloat = 16
    private let drawingAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { proxy in
            let drawingHeight = drawingSurfaceHeight(in: proxy.size)
            let controlsHeight = max(proxy.size.height - drawingHeight, minimumControlsHeight)

            VStack(spacing: 0) {
                if controlsPosition == .top {
                    controlsContent
                        .frame(height: controlsHeight)
                        .zIndex(1)
                    drawingSurface
                        .frame(height: drawingHeight)
                        .zIndex(0)
                } else {
                    drawingSurface
                        .frame(height: drawingHeight)
                        .zIndex(0)
                    controlsContent
                        .frame(height: controlsHeight)
                        .zIndex(1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .bottom)
        .persistentSystemOverlays(.hidden)
    }

    private var controlsContent: some View {
        ControlDeckView(
            connection: connection,
            showsControls: $showsControls,
            controlsPosition: $controlsPosition
        )
        .padding(.horizontal, 16)
    }

    private var drawingSurface: some View {
        PencilCaptureRepresentable(
            connection: connection,
            controlsPosition: controlsPosition,
            reservesControlDeckSpace: false
        )
        .background(Color.black)
        .frame(maxWidth: .infinity)
    }

    private func drawingSurfaceHeight(in size: CGSize) -> CGFloat {
        let activeWidth = max(size.width - drawingOuterPadding * 2, 0)
        let idealHeight = activeWidth / drawingAspectRatio + drawingOuterPadding * 2
        let maximumHeight = max(size.height - minimumControlsHeight, 0)
        return min(idealHeight, maximumHeight)
    }
}
