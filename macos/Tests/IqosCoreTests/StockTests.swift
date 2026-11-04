import XCTest
@testable import IqosCore

// Os mesmos casos de tests/test_stock.py.

private let now = DateComponents(calendar: .current, year: 2026, month: 11, day: 4, hour: 10).date!

private func kinds(_ alerts: [Alert]) -> [Alert.Kind] { alerts.map(\.kind) }

private func smoke(_ s: inout Stock, _ n: Int) -> [Alert.Kind] {
    var out: [Alert.Kind] = []
    for _ in 0..<n { out += kinds(s.consume(1)) }
    return out
}

final class StockTests: XCTestCase {
    func testNoStockNoAlerts() {
        var s = Stock()
        XCTAssertEqual(s.consume(3), [])
        XCTAssertNil(s.sticksLeft)
    }

    func testBuyThreeCartons() {
        var s = Stock(packSize: 20, packsPerCarton: 10)
        s.add(cartons: 3, now: now)
        XCTAssertEqual(s.sticksLeft, 600)
        XCTAssertEqual(s.describe(), "3 volumes")
        XCTAssertEqual(s.since, "2026-11-04")
        s.add(packs: 2)
        XCTAssertEqual(s.describe(), "3 volumes e 2 maços")
        XCTAssertEqual(s.describe(221), "1 volume, 1 maço e 1 stick")
    }

    func testPackLowOncePerPack() {
        var s = Stock(packSize: 10, packsPerCarton: 10, packWarnSticks: 2, lowStockPacks: 0)
        s.add(packs: 2, now: now)
        XCTAssertEqual(smoke(&s, 7), [])
        XCTAssertEqual(kinds(s.consume(1)), [.packLow])
        XCTAssertEqual(smoke(&s, 1), [])
        XCTAssertEqual(smoke(&s, 1), [])
        XCTAssertEqual(s.openPackLeft, 10)
        XCTAssertEqual(s.closedPacks, 0)
        XCTAssertEqual(smoke(&s, 7), [])
        let alerts = s.consume(1)
        XCTAssertEqual(kinds(alerts), [.packLow])
        XCTAssertTrue(alerts[0].message.contains("último maço"))
    }

    func testPackDoneWhenWarnIsZero() {
        var s = Stock(packSize: 10, packWarnSticks: 0, lowStockPacks: 0)
        s.add(packs: 2)
        XCTAssertEqual(smoke(&s, 9), [])
        let alerts = s.consume(1)
        XCTAssertEqual(kinds(alerts), [.packLow])
        XCTAssertEqual(alerts[0].title, "Maço acabado")
    }

    func testLowStockAtOneCarton() {
        var s = Stock(packSize: 10, packsPerCarton: 10, packWarnSticks: 0, lowStockPacks: 10)
        s.add(cartons: 3)
        XCTAssertEqual(smoke(&s, 200).filter { $0 == .stockLow }.count, 1)
        XCTAssertEqual(s.sticksLeft, 100)
        XCTAssertFalse(smoke(&s, 1).contains(.stockLow))
    }

    func testEmpty() {
        var s = Stock(packSize: 10, packWarnSticks: 0, lowStockPacks: 0)
        s.set(2)
        XCTAssertEqual(smoke(&s, 1), [])
        XCTAssertEqual(kinds(s.consume(5)), [.stockEmpty])
        XCTAssertEqual(s.sticksLeft, 0)
        XCTAssertEqual(s.consume(1), [])
    }

    func testNotifyOff() {
        var s = Stock(packSize: 10, notify: false)
        s.set(3)
        XCTAssertEqual(s.consume(3), [])
        XCTAssertEqual(s.sticksLeft, 0)
    }

    func testDaysLeft() {
        var s = Stock(packSize: 20)
        s.add(packs: 10, now: DateComponents(calendar: .current, year: 2026, month: 11, day: 1).date!)
        _ = s.consume(40)
        XCTAssertEqual(s.perDay(today: now), 10)
        XCTAssertEqual(s.daysLeft(today: now), 16)
    }

    func testSettingsRoundTripAndPythonFormat() throws {
        var st = Settings()
        st.stock.add(cartons: 1, now: now)
        let data = try JSONEncoder().encode(st)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data).stock, st.stock)
        // Ficheiro escrito pela app de Windows.
        let py = #"{"stock": {"sticks_left": 37, "pack_size": 10, "packs_per_carton": 10, "pack_warn_sticks": 2, "low_stock_packs": 10, "notify": true, "since": "2026-11-01", "consumed": 3}}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(py.utf8)).stock
        XCTAssertEqual(s.sticksLeft, 37)
        XCTAssertEqual(s.openPackLeft, 7)
        XCTAssertEqual(s.closedPacks, 3)
        // Ficheiro antigo, sem stock.
        XCTAssertNil(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).stock.sticksLeft)
    }
}
