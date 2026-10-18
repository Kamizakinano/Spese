import XCTest
@testable import Spese

/// Riepilogo di fine viaggio e conti con i compagni.
final class FineViaggioTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    func testViaggioAppenaFinito() {
        let t = Trip(name: "Breslavia", currency: "PLN", startDate: d(2026, 10, 16), endDate: d(2026, 10, 17))
        XCTAssertNil(recentlyEndedTrip([t], now: d(2026, 10, 17)), "Il giorno del rientro il viaggio è ancora in corso")
        XCTAssertEqual(recentlyEndedTrip([t], now: d(2026, 10, 18))?.name, "Breslavia")
        XCTAssertNotNil(recentlyEndedTrip([t], now: d(2026, 10, 20)))
        XCTAssertNil(recentlyEndedTrip([t], now: d(2026, 10, 21)), "Dopo tre giorni sparisce")
    }

    func testDaDoveVieneIlDebito() {
        let cena = Expense(amount: 24.72, categoryName: "Pranzi/Cene fuori", date: d(2026, 10, 16), note: "Cena")
        cena.paidBy = "Valentina"; cena.shares = ["Io": 12.36, "Valentina": 12.36]
        let taxi = Expense(amount: 10, categoryName: "Trasporti", date: d(2026, 10, 17), note: "Taxi")
        taxi.shares = ["Io": 5, "Valentina": 5]
        let mia = Expense(amount: 3, categoryName: "Alimentari", date: d(2026, 10, 17), note: "Acqua")
        let lines = tripDebtLines([cena, taxi, mia], with: "Valentina")
        XCTAssertEqual(lines.map(\.amount), [12.36, -5])
        XCTAssertEqual(lines.reduce(0) { $0 + $1.amount }, 7.36, accuracy: 0.001)
    }
}
