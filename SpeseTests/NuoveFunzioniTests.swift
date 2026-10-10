import XCTest
import SwiftData
@testable import Spese

/// Prove della versione 2.8: previsione, confronto, calendario, abbonamenti, registro e widget.
final class NuoveFunzioniTests: XCTestCase {
    private let cal = Calendar.current

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testPrevisioneDiFinePeriodo() {
        // Stipendio il 1° ottobre, prossimo il 31: oggi è il 10 (10 giorni passati, 21 da fare).
        let f = makeForecast(available: 900, spent: 300, period: (day(2026, 10, 1, 0), day(2026, 10, 31, 0)),
                             now: day(2026, 10, 10))
        XCTAssertEqual(f.elapsedDays, 10)
        XCTAssertEqual(f.daysLeft, 21)
        XCTAssertEqual(f.avgPerDay, 30, accuracy: 0.001)
        XCTAssertEqual(f.projected, 900 - 30 * 21, accuracy: 0.001)
        XCTAssertEqual(f.budgetPerDay, 900.0 / 21, accuracy: 0.001)
    }

    func testConfrontoStessiGiorniDelPeriodoPrecedente() {
        let a = Expense(amount: 50, categoryName: "Trasporti", date: day(2026, 10, 3), note: "")
        let b = Expense(amount: 40, categoryName: "Trasporti", date: day(2026, 9, 3), note: "")
        // Fuori dagli stessi giorni del periodo scorso: non conta.
        let c = Expense(amount: 999, categoryName: "Trasporti", date: day(2026, 9, 25), note: "")
        let d = Expense(amount: 20, categoryName: "Svago", date: day(2026, 10, 4), note: "")
        let out = compareCategories([a, b, c, d], current: (day(2026, 10, 1, 0), day(2026, 10, 31, 0)),
                                    previousStart: day(2026, 9, 1, 0), now: day(2026, 10, 5))
        let t = out.first { $0.name == "Trasporti" }
        XCTAssertEqual(t?.now, 50)
        XCTAssertEqual(t?.before, 40)
        XCTAssertEqual(t?.percent ?? 0, 25, accuracy: 0.001)
        XCTAssertNil(out.first { $0.name == "Svago" }?.percent, "Categoria nuova: nessuna percentuale")
    }

    func testCalendarioLivelli() {
        XCTAssertEqual(spendLevel(0, max: 80), 0)
        XCTAssertEqual(spendLevel(5, max: 80), 1)
        XCTAssertEqual(spendLevel(40, max: 80), 2)
        XCTAssertEqual(spendLevel(80, max: 80), 4)
        let e = [Expense(amount: 10, categoryName: "Altro", date: day(2026, 10, 9), note: ""),
                 Expense(amount: 5, categoryName: "Altro", date: day(2026, 10, 9), note: ""),
                 Expense(amount: 7, categoryName: "Altro", date: day(2026, 11, 9), note: "")]
        XCTAssertEqual(dailyTotals(e, month: day(2026, 10, 1))[9], 15)
    }

    func testProssimoRinnovo() {
        XCTAssertEqual(nextRenewal(nextKey: "2026-11", day: 13), day(2026, 11, 13))
        XCTAssertEqual(nextRenewal(nextKey: "2027-02", day: 31), day(2027, 2, 28), "Nei mesi corti vale l'ultimo giorno")
        XCTAssertNil(nextRenewal(nextKey: "", day: 1))
    }

    func testRegistroTieneLeUltime50() {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        for i in 0..<60 { ApplePayLog.begin(amount: "\(i)", merchant: "x", defaults: d) }
        let all = ApplePayLog.all(d)
        XCTAssertEqual(all.count, 50)
        XCTAssertEqual(all.first?.amount, "59", "Le più recenti per prime")
        ApplePayLog.finish(all[0].id, "Registrata: prova", defaults: d)
        XCTAssertEqual(ApplePayLog.all(d).first?.result, "Registrata: prova")
    }

    func testNumeriDelWidget() {
        let now = day(2026, 10, 10)
        let s = WidgetSnapshot(available: 300, periodStart: day(2026, 9, 27, 0), periodEnd: day(2026, 10, 20, 0),
                               spentSincePay: 120, updated: now)
        XCTAssertEqual(s.remainingDays(now: now), 10)
        XCTAssertEqual(s.perDay(now: now), 30, accuracy: 0.001)
        XCTAssertEqual(WidgetSnapshot(available: -5, periodStart: nil, periodEnd: nil, spentSincePay: 0, updated: now).perDay(now: now), 0)
    }

    func testGiftCardTraLeCategorie() {
        XCTAssertTrue(defaultCategories.contains { $0.0 == giftCardCategory && $0.1 == "giftcard" })
        XCTAssertEqual(defaultCategories.last?.0, "Altro", "Altro resta l'ultima")
    }
}
