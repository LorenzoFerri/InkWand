import XCTest
@testable import InkWandCore

final class InkWandCoreTests: XCTestCase {
    func testMessageJSONLineRoundTrip() throws {
        let message = InkMessage.sample(PencilSample(phase: .moved, tool: .eraser, x: 0.25, y: 0.75, pressure: 0.5, timestamp: 42))
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testPencilSampleDefaultsToPenWhenToolIsMissing() throws {
        let line = #"{"payload":{"phase":"moved","pressure":0.5,"timestamp":42,"x":0.25,"y":0.75},"type":"sample"}"#
        let message = try JSONLineCodec.decodeLine(line)

        XCTAssertEqual(message, .sample(PencilSample(phase: .moved, tool: .pen, x: 0.25, y: 0.75, pressure: 0.5, timestamp: 42)))
    }

    func testToolMessageJSONLineRoundTrip() throws {
        let message = InkMessage.tool(.eraser)
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testPadMessageJSONLineRoundTrip() throws {
        let message = InkMessage.pad(.brushLarger)
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testGestureMessageJSONLineRoundTrip() throws {
        let message = InkMessage.gesture(
            CanvasGesture(
                phase: .moved,
                x: 0.4,
                y: 0.6,
                translationX: 0.01,
                translationY: -0.02,
                scale: 1.03,
                rotation: 0.05,
                firstTouchX: 0.35,
                firstTouchY: 0.55,
                secondTouchX: 0.45,
                secondTouchY: 0.65,
                timestamp: 99
            )
        )
        let data = try JSONLineCodec.encode(message)

        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(try JSONLineCodec.decodeLine(data), message)
    }

    func testTouchMessageJSONLineRoundTrip() throws {
        let message = InkMessage.touch(
            TouchSample(
                id: 7,
                phase: .moved,
                x: 0.2,
                y: 0.8,
                pressure: 0.75,
                width: 0.03,
                height: 0.02,
                timestamp: 123
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

    func testExistingMessageTypesDecodeAfterGestureAddition() throws {
        XCTAssertEqual(
            try JSONLineCodec.decodeLine(#"{"payload":{"phase":"moved","pressure":0.5,"timestamp":42,"x":0.25,"y":0.75},"type":"sample"}"#),
            .sample(PencilSample(phase: .moved, tool: .pen, x: 0.25, y: 0.75, pressure: 0.5, timestamp: 42))
        )
        XCTAssertEqual(try JSONLineCodec.decodeLine(#"{"payload":"eraser","type":"tool"}"#), .tool(.eraser))
        XCTAssertEqual(try JSONLineCodec.decodeLine(#"{"payload":"undo","type":"pad"}"#), .pad(.undo))
        XCTAssertEqual(try JSONLineCodec.decodeLine(#"{"type":"cancel"}"#), .cancel)
    }

    func testTouchMessageDecodesAfterGestureCompatibility() throws {
        let line = #"{"payload":{"height":0.02,"id":5,"phase":"began","pressure":1,"timestamp":55,"width":0.02,"x":0.1,"y":0.9},"type":"touch"}"#
        let message = try JSONLineCodec.decodeLine(line)

        XCTAssertEqual(message, .touch(TouchSample(id: 5, phase: .began, x: 0.1, y: 0.9, pressure: 1, width: 0.02, height: 0.02, timestamp: 55)))
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
