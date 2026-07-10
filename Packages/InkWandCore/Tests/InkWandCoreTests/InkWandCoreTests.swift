import XCTest
@testable import InkWandCore

final class InkWandCoreTests: XCTestCase {
    func testMessageJSONLineRoundTrip() throws {
        let message = InkMessage.sample(PencilSample(phase: .moved, tool: .eraser, x: 0.25, y: 0.75, pressure: 0.5, timestamp: 42))
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testPencilSampleRequiresTool() throws {
        let line = #"{"payload":{"phase":"moved","pressure":0.5,"timestamp":42,"x":0.25,"y":0.75},"type":"sample"}"#

        XCTAssertThrowsError(try JSONLineCodec.decodeLine(line))
    }

    func testToolMessageJSONLineRoundTrip() throws {
        let message = InkMessage.tool(.eraser)
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testPadMessageJSONLineRoundTrip() throws {
        let message = InkMessage.pad(.opacityHigher)
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testHelloMessageJSONLineRoundTrip() throws {
        let message = InkMessage.hello(
            TabletHello(
                protocolVersion: inkWandProtocolVersion,
                canvasWidth: 1024,
                canvasHeight: 768,
                deviceName: "iPad"
            )
        )
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testTouchFrameMessageJSONLineRoundTrip() throws {
        let message = InkMessage.touchFrame([
            TouchSample(
                id: 7,
                phase: .moved,
                x: 0.2,
                y: 0.8,
                pressure: 0.75,
                width: 0.03,
                height: 0.02,
                timestamp: 123
            ),
            TouchSample(
                id: 8,
                phase: .moved,
                x: 0.4,
                y: 0.6,
                pressure: 0.8,
                width: 0.04,
                height: 0.03,
                timestamp: 123
            ),
        ])
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testSupportedMessageTypesDecode() throws {
        XCTAssertEqual(
            try JSONLineCodec.decodeLine(#"{"payload":{"phase":"moved","pressure":0.5,"timestamp":42,"tool":"pen","x":0.25,"y":0.75},"type":"sample"}"#),
            .sample(PencilSample(phase: .moved, tool: .pen, x: 0.25, y: 0.75, pressure: 0.5, timestamp: 42))
        )
        XCTAssertEqual(try JSONLineCodec.decodeLine(#"{"payload":"eraser","type":"tool"}"#), .tool(.eraser))
        XCTAssertEqual(try JSONLineCodec.decodeLine(#"{"payload":"undo","type":"pad"}"#), .pad(.undo))
        XCTAssertEqual(try JSONLineCodec.decodeLine(#"{"type":"cancel"}"#), .cancel)
    }

    func testWireEncryptionPolicy() {
        XCTAssertFalse(InkMessage.authRequest(AuthRequest(serverID: "server", clientID: "client", clientName: "iPad", trustToken: "token")).shouldEncryptOnWire)
        XCTAssertFalse(InkMessage.encrypted(EncryptedMessage(nonce: "n", ciphertext: "c", tag: "t")).shouldEncryptOnWire)
        XCTAssertTrue(InkMessage.hello(TabletHello(protocolVersion: inkWandProtocolVersion, canvasWidth: 1, canvasHeight: 1, deviceName: "iPad")).shouldEncryptOnWire)
        XCTAssertTrue(InkMessage.touchFrame([]).shouldEncryptOnWire)
    }

    func testTabletMapperUsesNativeAbsoluteSpace() {
        let mapper = TabletMapper()
        let event = mapper.map(PencilSample(phase: .moved, x: 0.5, y: 0.25, pressure: 0.75, timestamp: 1))

        XCTAssertEqual(event.x, 32768, accuracy: 1)
        XCTAssertEqual(event.y, 16384, accuracy: 1)
        XCTAssertEqual(event.pressure, 49151, accuracy: 1)
        XCTAssertTrue(event.isTouching)
        XCTAssertTrue(event.isToolPresent)
    }

    func testTabletMapperClampsInputValues() {
        let mapper = TabletMapper()
        let event = mapper.map(PencilSample(phase: .moved, x: -0.5, y: 1.5, pressure: 2, timestamp: 1))

        XCTAssertEqual(event.x, 0)
        XCTAssertEqual(event.y, 65535)
        XCTAssertEqual(event.pressure, 65535)
    }

    func testTabletMapperPreservesToolMode() {
        let mapper = TabletMapper()
        let event = mapper.map(PencilSample(phase: .moved, tool: .eraser, x: 0.5, y: 0.5, pressure: 1, timestamp: 1))

        XCTAssertEqual(event.tool, .eraser)
        XCTAssertTrue(event.isTouching)
        XCTAssertTrue(event.isToolPresent)
    }

    func testTabletMapperReleasesToolOnEndedAndCancelled() {
        let mapper = TabletMapper()

        let ended = mapper.map(PencilSample(phase: .ended, x: 0.5, y: 0.5, pressure: 1, timestamp: 1))
        XCTAssertEqual(ended.pressure, 0)
        XCTAssertFalse(ended.isTouching)
        XCTAssertFalse(ended.isToolPresent)

        let cancelled = mapper.map(PencilSample(phase: .cancelled, x: 0.5, y: 0.5, pressure: 1, timestamp: 1))
        XCTAssertEqual(cancelled.pressure, 0)
        XCTAssertFalse(cancelled.isTouching)
        XCTAssertFalse(cancelled.isToolPresent)
    }

    func testTiltIsDerivedFromAltitudeAndAzimuth() {
        let mapper = TabletMapper()

        let vertical = mapper.map(
            PencilSample(phase: .moved, x: 0.5, y: 0.5, pressure: 1, timestamp: 1, altitude: .pi / 2, azimuth: 0)
        )
        XCTAssertEqual(vertical.tiltX, 0)
        XCTAssertEqual(vertical.tiltY, 0)

        let tiltedRight = mapper.map(
            PencilSample(phase: .moved, x: 0.5, y: 0.5, pressure: 1, timestamp: 1, altitude: .pi / 4, azimuth: 0)
        )
        XCTAssertEqual(tiltedRight.tiltX, 45)
        XCTAssertEqual(tiltedRight.tiltY, 0)

        let tiltedDown = mapper.map(
            PencilSample(phase: .moved, x: 0.5, y: 0.5, pressure: 1, timestamp: 1, altitude: .pi / 4, azimuth: .pi / 2)
        )
        XCTAssertEqual(tiltedDown.tiltX, 0)
        XCTAssertEqual(tiltedDown.tiltY, 45)
    }
}
