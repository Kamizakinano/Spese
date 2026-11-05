import XCTest
@testable import Spese

/// Prove della scelta Carta / Contanti nella Previsione (2.61).
final class PrevisioneSceltaTests: XCTestCase {
    func testQualiSpeseContano() {
        let carta = Expense(amount: 10, categoryName: "Alimentari", date: Date(), note: "")
        let cash = Expense(amount: 5, categoryName: "Alimentari", date: Date(), note: "")
        cash.method = "contanti"
        XCTAssertTrue(ForecastScope.carta.includes(carta))
        XCTAssertFalse(ForecastScope.carta.includes(cash))
        XCTAssertTrue(ForecastScope.contanti.includes(cash))
        XCTAssertFalse(ForecastScope.contanti.includes(carta))
        XCTAssertTrue(ForecastScope.entrambi.includes(carta) && ForecastScope.entrambi.includes(cash))
    }
}
