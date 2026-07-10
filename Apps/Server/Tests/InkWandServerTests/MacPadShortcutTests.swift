#if os(macOS)
import InkWandCore
@testable import InkWandServer
import XCTest

final class MacPadShortcutTests: XCTestCase {
    func testDefaultPadShortcutsUseMacKeyCodes() {
        XCTAssertEqual(MacPadShortcut.shortcut(for: .undo), MacPadShortcut(keyCode: 6, command: true))
        XCTAssertEqual(MacPadShortcut.shortcut(for: .redo), MacPadShortcut(keyCode: 6, command: true, shift: true))
        XCTAssertEqual(MacPadShortcut.shortcut(for: .brushSmaller), MacPadShortcut(keyCode: 33))
        XCTAssertEqual(MacPadShortcut.shortcut(for: .brushLarger), MacPadShortcut(keyCode: 30))
        XCTAssertEqual(MacPadShortcut.shortcut(for: .opacityLower), MacPadShortcut(keyCode: 34))
        XCTAssertEqual(MacPadShortcut.shortcut(for: .opacityHigher), MacPadShortcut(keyCode: 31))
        XCTAssertEqual(MacPadShortcut.shortcut(for: .panBegan), MacPadShortcut(keyCode: 49))
        XCTAssertEqual(MacPadShortcut.shortcut(for: .panEnded), MacPadShortcut(keyCode: 49))
    }
}
#endif
