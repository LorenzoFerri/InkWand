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

    func testTabletMapperUsesNativeAbsoluteSpace() {
        let mapper = TabletMapper()
        let event = mapper.map(PencilSample(phase: .moved, x: 0.5, y: 0.25, pressure: 0.75, timestamp: 1))

        XCTAssertEqual(event.x, 16384, accuracy: 1)
        XCTAssertEqual(event.y, 8192, accuracy: 1)
        XCTAssertEqual(event.pressure, 3072)
        XCTAssertTrue(event.isTouching)
        XCTAssertTrue(event.isToolPresent)
    }

    func testTabletMapperClampsInputValues() {
        let mapper = TabletMapper()
        let event = mapper.map(PencilSample(phase: .moved, x: -0.5, y: 1.5, pressure: 2, timestamp: 1))

        XCTAssertEqual(event.x, 0)
        XCTAssertEqual(event.y, 32767)
        XCTAssertEqual(event.pressure, 4096)
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
