#if os(macOS)
@testable import InkWandServer
import XCTest

final class MacTabletEventPenDeviceTests: XCTestCase {
    func testTabletMouseSubtypeSequenceIncludesRelease() {
        XCTAssertEqual(MacTabletEventPenDevice.mouseEventType(wasTouching: false, isTouching: true), .leftMouseDown)
        XCTAssertEqual(MacTabletEventPenDevice.mouseEventType(wasTouching: true, isTouching: true), .leftMouseDragged)
        XCTAssertEqual(MacTabletEventPenDevice.mouseEventType(wasTouching: true, isTouching: false), .leftMouseUp)
        XCTAssertEqual(MacTabletEventPenDevice.mouseEventType(wasTouching: false, isTouching: false), .mouseMoved)
    }
}
#endif
