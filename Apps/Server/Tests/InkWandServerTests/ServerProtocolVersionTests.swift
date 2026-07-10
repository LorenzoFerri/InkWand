import InkWandCore
@testable import InkWandServer
import XCTest

final class ServerProtocolVersionTests: XCTestCase {
    func testUnsupportedProtocolVersionErrorNamesExpectedVersion() {
        XCTAssertEqual(
            String(describing: ServerError.unsupportedProtocolVersion(1)),
            "Unsupported InkWand protocol version 1; expected \(inkWandProtocolVersion)."
        )
    }
}
