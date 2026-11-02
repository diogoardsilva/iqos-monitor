import XCTest
@testable import IqosCore

private let now = DateComponents(calendar: .current, year: 2026, month: 10, day: 30, hour: 12).date!
private let low = 20

private func kinds(_ alerts: [Alert]) -> [Alert.Kind] { alerts.map(\.kind) }

final class TrackerTests: XCTestCase {
    func testStickEndFromDeviceCounter() {
        var d = DeviceState(address: "A", name: "IQOS ILUMA")
        _ = d.onBattery(BatteryStatus(80, 100, true), now: now, lowPct: low)
        XCTAssertEqual(d.onTelemetry(Telemetry(smokingCount: 100), now: now, lowPct: low), [])
        _ = d.onBattery(BatteryStatus(80, nil, false), now: now, lowPct: low)
        let alerts = d.onTelemetry(Telemetry(smokingCount: 101), now: now, lowPct: low)
        XCTAssertEqual(kinds(alerts), [.stickEnd, .holderCharge])
        XCTAssertEqual(d.sticksToday, 1)
        XCTAssertEqual(d.sticksSinceCharge, 1)
    }

    func testIlumaIAllowsTwoSticksBeforeHolderAlert() {
        var d = DeviceState(address: "A", name: "IQOS ILUMA i")
        _ = d.onBattery(BatteryStatus(80, 100, true), now: now, lowPct: low)
        _ = d.onTelemetry(Telemetry(smokingCount: 10), now: now, lowPct: low)
        _ = d.onBattery(BatteryStatus(80, nil, false), now: now, lowPct: low)
        XCTAssertEqual(kinds(d.onTelemetry(Telemetry(smokingCount: 11), now: now, lowPct: low)), [.stickEnd])
        XCTAssertTrue(kinds(d.onTelemetry(Telemetry(smokingCount: 12), now: now, lowPct: low))
            .contains(.holderCharge))
    }

    func testFallbackCountWithoutTelemetry() {
        var d = DeviceState(address: "A", name: "IQOS ILUMA")
        _ = d.onBattery(BatteryStatus(80, 100, true), now: now, lowPct: low)
        _ = d.onBattery(BatteryStatus(80, nil, false), now: now, lowPct: low)
        let alerts = d.onBattery(BatteryStatus(76, 10, true), now: now, lowPct: low)
        XCTAssertEqual(kinds(alerts), [.stickEnd, .holderIn])
        XCTAssertEqual(d.holderSticksSinceCharge, 0)
    }

    func testLowBatteryAlertOnceAndResetOnCharge() {
        var d = DeviceState(address: "A", name: "IQOS ILUMA ONE")
        XCTAssertEqual(kinds(d.onBattery(BatteryStatus(25, nil, false), now: now, lowPct: low)), [])
        XCTAssertEqual(kinds(d.onBattery(BatteryStatus(19, nil, false), now: now, lowPct: low)), [.lowBattery])
        XCTAssertEqual(d.onBattery(BatteryStatus(18, nil, false), now: now, lowPct: low), [])
        _ = d.onBattery(BatteryStatus(30, nil, false), now: now, lowPct: low)
        XCTAssertEqual(d.sticksSinceCharge, 0)
        XCTAssertEqual(kinds(d.onBattery(BatteryStatus(100, nil, false), now: now, lowPct: low)), [.charged])
    }

    func testRemainingEstimateAndLearning() {
        var d = DeviceState(address: "A", name: "IQOS ILUMA ONE")
        _ = d.onBattery(BatteryStatus(100, nil, false), now: now, lowPct: low)
        XCTAssertEqual(d.sticksRemaining, 20)
        _ = d.onTelemetry(Telemetry(smokingCount: 1), now: now, lowPct: low)
        var count = 1
        for pct in stride(from: 90, to: 40, by: -10) {
            count += 1
            _ = d.onBattery(BatteryStatus(pct, nil, false), now: now, lowPct: low)
            _ = d.onTelemetry(Telemetry(smokingCount: count), now: now, lowPct: low)
        }
        XCTAssertGreaterThan(d.pctPerStick, 7)
        XCTAssertLessThanOrEqual(d.sticksRemaining ?? 99, 6)
    }

    func testDayRollover() {
        var d = DeviceState(address: "A", name: "IQOS ILUMA ONE")
        _ = d.onBattery(BatteryStatus(90, nil, false), now: now, lowPct: low)
        _ = d.onTelemetry(Telemetry(smokingCount: 1), now: now, lowPct: low)
        _ = d.onTelemetry(Telemetry(smokingCount: 2), now: now, lowPct: low)
        XCTAssertEqual(d.sticksToday, 1)
        _ = d.onTelemetry(Telemetry(smokingCount: 3), now: now.addingTimeInterval(86_400), lowPct: low)
        XCTAssertEqual(d.sticksToday, 1)
        XCTAssertEqual(d.sticksSinceCharge, 2)
    }

    func testPersistenceRoundtrip() throws {
        var s = Settings()
        s.devices = [DeviceState(address: "A", name: "IQOS ILUMA", alias: "Casa", sticksToday: 3)]
        let e = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(e.devices.first?.alias, "Casa")
        XCTAssertEqual(e.devices.first?.sticksToday, 3)
        XCTAssertEqual(e.devices.first?.pctPerStick, 5.0)
    }

    func testReadsStateWrittenByWindowsApp() throws {
        let json = #"{"low_battery_pct": 15, "devices": [{"address": "X", "name": "IQOS ILUMA i",
                     "alias": "Carro", "pct_per_stick": 4.2, "smoking_count": 77}]}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.lowBatteryPct, 15)
        XCTAssertEqual(s.pollSeconds, 20)
        XCTAssertEqual(s.devices.first?.smokingCount, 77)
        XCTAssertEqual(s.devices.first?.pctPerStick, 4.2)
    }

    func testHolderOutAndInEvents() {
        var d = DeviceState(address: "A", name: "IQOS ILUMA PRIME")
        XCTAssertEqual(kinds(d.onBattery(BatteryStatus(80, 100, true), now: now, lowPct: low)), [])
        XCTAssertEqual(kinds(d.onBattery(BatteryStatus(80, nil, false), now: now, lowPct: low)), [.holderOut])
        XCTAssertTrue(d.holderReady)
        XCTAssertEqual(d.holderPct, 100)
        XCTAssertEqual(kinds(d.onBattery(BatteryStatus(80, 85, true), now: now, lowPct: low)), [.holderIn])
        XCTAssertFalse(d.holderReady)
    }
}
