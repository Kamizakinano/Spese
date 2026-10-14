import XCTest
@testable import Spese

/// La pagina di una categoria mostra le spese del mese, fino a oggi, dalla più recente.
final class CategorieTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: 12))!
    }

    func testSpeseDellaCategoriaNelMese() {
        let ex = [
            Expense(amount: 7.10, categoryName: "Alimentari", date: d(2026, 10, 14), note: "Pausa Lavoro"),
            Expense(amount: 6.89, categoryName: "Alimentari", date: d(2026, 10, 3), note: "Lidl"),
            Expense(amount: 20, categoryName: "Svago", date: d(2026, 10, 5), note: "Cinema"),
            Expense(amount: 9, categoryName: "Alimentari", date: d(2026, 9, 30), note: "Mese prima"),
            Expense(amount: 50, categoryName: "Alimentari", date: d(2026, 10, 25), note: "In arrivo")
        ]
        let r = categoryExpenses(ex, trips: [], category: "Alimentari", month: d(2026, 10, 1), now: d(2026, 10, 14))
        XCTAssertEqual(r.map(\.note), ["Pausa Lavoro", "Lidl"])
    }
}
