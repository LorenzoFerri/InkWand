#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

struct PencilCaptureRepresentable: UIViewRepresentable {
    let connection: TabletConnection
    let controlsPosition: ControlsPosition
    let reservesControlDeckSpace: Bool

    func makeUIView(context: Context) -> PencilSurfaceView {
        let view = PencilSurfaceView()
        view.connection = connection
        view.controlsPosition = controlsPosition
        view.reservesControlDeckSpace = reservesControlDeckSpace
        return view
    }

    func updateUIView(_ uiView: PencilSurfaceView, context: Context) {
        uiView.connection = connection
        uiView.controlsPosition = controlsPosition
        uiView.reservesControlDeckSpace = reservesControlDeckSpace
    }
}
#endif
