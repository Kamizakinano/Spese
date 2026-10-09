import XCTest
@testable import Spese

/// Prove del calcolo del periodo tra uno stipendio e l'altro, con date fisse.
final class PayPeriodTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: hour))!
    }
    private func day0(_ y: Int, _ m: Int, _ day: Int) -> Date { d(y, m, day, hour: 0) }

    func testProssimoStipendio() {
        XCTAssertEqual(nextPayday(day: 10, from: d(2026, 10, 9)), day0(2026, 10, 10))
        XCTAssertEqual(nextPayday(day: 10, from: d(2026, 10, 10)), day0(2026, 11, 10), "Il giorno dello stipendio conta già il mese dopo")
        XCTAssertEqual(nextPayday(day: 31, from: d(2027, 2, 15)), day0(2027, 2, 28), "Nei mesi corti vale l'ultimo giorno")
        XCTAssertEqual(nextPayday(day: 10, from: d(2026, 12, 20)), day0(2027, 1, 10), "Passaggio d'anno")
    }

    func testUltimoStipendio() {
        XCTAssertEqual(lastPayday(day: 10, from: d(2026, 10, 9)), day0(2026, 9, 10))
        XCTAssertEqual(lastPayday(day: 10, from: d(2026, 10, 10)), day0(2026, 10, 10))
        XCTAssertEqual(lastPayday(day: 31, from: d(2026, 3, 1)), day0(2026, 2, 28))
    }

    func testPeriodoScelto() {
        // Stipendio arrivato il 9 ottobre, il prossimo il 10 novembre.
        let p = payPeriod(day: 10, customStart: d(2026, 10, 9), customEnd: d(2026, 11, 10), now: d(2026, 10, 9))
        XCTAssertEqual(p?.start, day0(2026, 10, 9))
        XCTAssertEqual(p?.end, day0(2026, 11, 10))
        XCTAssertEqual(daysLeft(until: p!.end, from: d(2026, 10, 9)), 32)
        XCTAssertEqual(daysLeft(until: p!.end, from: d(2026, 11, 9)), 1, "L'ultimo giorno resta 1 giorno")
    }

    func testPeriodoFinitoTornaAutomatico() {
        // Il periodo scelto è finito: si usa il giorno di accredito.
        let p = payPeriod(day: 10, customStart: d(2026, 10, 9), customEnd: d(2026, 11, 10), now: d(2026, 11, 12))
        XCTAssertEqual(p?.start, day0(2026, 11, 10))
        XCTAssertEqual(p?.end, day0(2026, 12, 10))
    }

    func testPeriodoAutomatico() {
        let p = payPeriod(day: 10, customStart: nil, customEnd: nil, now: d(2026, 10, 9))
        XCTAssertEqual(p?.start, day0(2026, 9, 10))
        XCTAssertEqual(p?.end, day0(2026, 10, 10))
        XCTAssertEqual(daysLeft(until: p!.end, from: d(2026, 10, 9)), 1)
    }
}
