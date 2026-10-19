import XCTest
@testable import Spese

/// Dettaglio di una categoria: intervalli e totali per giorno.
final class CategoriaDettaglioTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }
    private func midnight(_ y: Int, _ m: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day))!
    }

    func testIntervalli() {
        let now = d(2026, 10, 19)   // lunedì
        XCTAssertEqual(scaleRange(.giorno, anchor: now, back: 1, payDay: nil).start, midnight(2026, 10, 18))
        let w = scaleRange(.settimana, anchor: now, back: 1, payDay: nil)
        XCTAssertEqual(w.start, midnight(2026, 10, 12))
        XCTAssertEqual(w.end, midnight(2026, 10, 19))
        let m = scaleRange(.mese, anchor: now, back: 1, payDay: nil)
        XCTAssertEqual(m.start, midnight(2026, 9, 1))
        XCTAssertEqual(m.end, midnight(2026, 10, 1))
        XCTAssertEqual(rangeText(w), "\(midnight(2026, 10, 12).formatted(.dateTime.day().month(.abbreviated))) – \(midnight(2026, 10, 18).formatted(.dateTime.day().month(.abbreviated)))")
    }

    func testTotaliPerGiorno() {
        let a = Expense(amount: 10, categoryName: "Alimentari", date: d(2026, 10, 13), note: "")
        let b = Expense(amount: 5, categoryName: "Alimentari", date: d(2026, 10, 13, 18), note: "")
        let c = Expense(amount: 7, categoryName: "Alimentari", date: d(2026, 10, 18), note: "")
        let r = (start: midnight(2026, 10, 12), end: midnight(2026, 10, 19))
        XCTAssertEqual(dailyCategoryTotals([a, b, c], range: r), [0, 15, 0, 0, 0, 0, 7])
    }
}
