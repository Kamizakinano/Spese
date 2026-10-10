import XCTest
@testable import Spese

/// Prove della sezione Stipendi ricevuti.
final class StipendiTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testStipendiPerMeseEMedia() {
        let list = [
            Income(amount: 1500, saved: 0, kind: "Stipendio", date: day(2026, 8, 27), note: ""),
            Income(amount: 1600, saved: 0, kind: "Stipendio", date: day(2026, 9, 27), note: ""),
            Income(amount: 200, saved: 0, kind: "Stipendio", date: day(2026, 9, 30), note: "straordinari"),
            Income(amount: 1550, saved: 0, kind: "Stipendio", date: day(2026, 10, 9), note: ""),
            Income(amount: 900, saved: 0, kind: "Altra entrata", date: day(2026, 10, 1), note: ""),
            Income(amount: 3000, saved: 0, kind: initialKind, date: day(2026, 8, 1), note: "")
        ]
        let m = salaryMonths(list)
        XCTAssertEqual(m.count, 3, "Solo gli stipendi, uno per mese")
        XCTAssertEqual(m.first?.total, 1550, "Il più recente per primo")
        XCTAssertEqual(m[1].total, 1800, "Due accrediti nello stesso mese si sommano")
        XCTAssertEqual(salaryAverage(m), (1500 + 1800 + 1550) / 3.0, accuracy: 0.001)
        XCTAssertEqual(salaryAverage([]), 0)
    }

    func testImportoPerIlCampo() {
        XCTAssertEqual(amountString(1250), "1250")
        XCTAssertEqual(amountString(1250.5), "1250,50")
        XCTAssertEqual(parseAmount(amountString(1234.56)), 1234.56)
    }
}
