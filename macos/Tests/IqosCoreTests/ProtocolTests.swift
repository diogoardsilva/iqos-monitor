import XCTest
@testable import IqosCore

final class ProtocolTests: XCTestCase {
    func testBatteryFrameWithHolderInCharger() {
        XCTAssertEqual(parseBattery(Data([0, 0, 80, 0, 0, 0, 100])), BatteryStatus(80, 100, true))
    }

    func testBatteryFrameWithoutHolder() {
        XCTAssertEqual(parseBattery(Data([0, 0, 42, 0])), BatteryStatus(42, nil, false))
    }

    func testBatteryFrameTooShort() {
        XCTAssertNil(parseBattery(Data([0, 1])))
    }

    func testBatteryVoltageFrame() {
        let t = parseResponse(Data([0x00, 0x08, 0x88, 0x21, 0x00, 0xA8, 0x10, 0x00, 0x00]))
        XCTAssertEqual(t.batteryVoltage ?? 0, 4.264, accuracy: 0.0001)
    }

    func testTimestampFrame() {
        XCTAssertEqual(parseResponse(Data([0x00, 0x08, 0x80, 0x02, 0x1E, 0x00, 0, 0])).daysUsed, 30)
    }

    static func telemetryFrame(count: Int, days: Int) -> Data {
        var d: [UInt8] = [0x00, 0x08, 0x90, 0x22, 0x01, 0x01]
        for (tag, value) in [(UInt8(0x8E), count), (0x17, days), (0x01, 7), (0x02, 9)] {
            d += [0, 0, 0, 0, UInt8(value & 0xFF), UInt8(value >> 8), 0, tag]
        }
        return Data(d)
    }

    func testTelemetryFrame() {
        let f = Self.telemetryFrame(count: 1234, days: 99)
        XCTAssertEqual(f.count, 38)
        XCTAssertEqual(telemetryExpectedLength(f), 38)
        let t = parseResponse(f)
        XCTAssertEqual(t.smokingCount, 1234)
        XCTAssertEqual(t.daysUsed, 99)
    }

    func testIncompleteTelemetryIsIgnored() {
        XCTAssertNil(parseResponse(Self.telemetryFrame(count: 5, days: 5).prefix(20)).smokingCount)
    }

    func testUnknownFrameIsIgnored() {
        XCTAssertEqual(parseResponse(Data([0, 8, 0xFF, 0xFF, 0, 0])), Telemetry())
    }

    func testModels() {
        XCTAssertEqual(Model.from(name: "IQOS ILUMA i PRIME"), .ilumaIPrime)
        XCTAssertTrue(Model.from(name: "IQOS ILUMA i ONE").onePiece)
        XCTAssertEqual(Model.from(name: "IQOS ILUMA ONE"), .ilumaOne)
        XCTAssertEqual(Model.from(name: "IQOS ILUMA").sticksPerHolderCharge, 1)
        XCTAssertEqual(Model.from(name: "IQOS ILUMA i").sticksPerHolderCharge, 2)
        XCTAssertTrue(looksLikeIqos(name: nil, serviceUUIDs: ["daebb240-b041-11e4-9e45-0002a5d5c51b"]))
        XCTAssertFalse(looksLikeIqos(name: "Headphones"))
    }
}
