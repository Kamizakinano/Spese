import XCTest
@testable import Spese

/// Spese "Ti devono" già restituite: per me conta solo la differenza.
final class RestituiteTests: XCTestCase {
    func testGiftCardRestituita() {
        let g = Expense(amount: 475, categoryName: "Gift Card", date: Date(), note: "Gift Ikea Vale")
        g.owedBy = "Valentina"; g.owedAmount = 475
        XCTAssertEqual(refundedPart(g), 0, "Non ancora restituita")
        XCTAssertEqual(everydaySpend(g), 475)
        g.settled = true
        XCTAssertEqual(refundedPart(g), 475)
        XCTAssertEqual(everydaySpend(g), 0)
        let meta = Expense(amount: 40, categoryName: "Altro", date: Date(), note: "Cena")
        meta.owedAmount = 20; meta.settled = true
        XCTAssertEqual(everydaySpend(meta), 20)
    }
}
