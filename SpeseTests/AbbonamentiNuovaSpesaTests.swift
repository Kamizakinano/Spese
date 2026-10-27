import XCTest
@testable import Spese

/// Prove della categoria Abbonamenti in "Nuova spesa" (2.58).
final class AbbonamentiNuovaSpesaTests: XCTestCase {
    func testAbbonamentoParteDalMeseDopo() {
        let d = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 27, hour: 12))!
        let r = makeSubscription(note: " SIM Iliad ", amount: 9.99, date: d)
        XCTAssertEqual(r.name, "SIM Iliad")
        XCTAssertEqual(r.amount, 9.99)
        XCTAssertEqual(r.day, 27)
        XCTAssertEqual(r.nextKey, "2027-01", "Il mese di oggi è già segnato")
        XCTAssertTrue(r.isSubscription)
        XCTAssertEqual(r.categoryName, subscriptionCategory)
        XCTAssertEqual(makeSubscription(note: "", amount: 5, date: d).name, "Abbonamento")
        XCTAssertTrue(defaultCategories.contains { $0.0 == subscriptionCategory })
    }
}
