import XCTest
@testable import Spese

/// Il riquadro del viaggio in Home compare da mezzanotte del primo giorno.
final class ViaggioHomeTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min))!
    }

    func testCompareAllaMezzanotteDelPrimoGiorno() {
        let t = Trip(name: "Barcellona", currency: "EUR", startDate: d(2026, 10, 16, 15), endDate: d(2026, 10, 20, 9))
        XCTAssertNil(activeTrip([t], now: d(2026, 10, 15, 23, 59)), "Il 15 alle 23:59 non c'è ancora")
        XCTAssertEqual(activeTrip([t], now: d(2026, 10, 16, 0, 0))?.name, "Barcellona", "Allo scattare del 16 compare")
        XCTAssertNotNil(activeTrip([t], now: d(2026, 10, 20, 23, 59)), "Resta per tutto l'ultimo giorno")
        XCTAssertNil(activeTrip([t], now: d(2026, 10, 21, 0, 0)))
    }
}
