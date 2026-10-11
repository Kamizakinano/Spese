import XCTest
@testable import Spese

/// Prove della previsione: spese per altri e spese ricorrenti.
final class PrevisioneTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testSpesePerAltriERicorrentiFuoriDallaMedia() {
        let cena = Expense(amount: 80, categoryName: "Pranzi/Cene fuori", date: Date(), note: "Cena")
        cena.owedBy = "Marco"; cena.owedAmount = 40
        let affitto = Expense(amount: 500, categoryName: "Casa e bollette", date: Date(), note: "Affitto")
        let rec = [Recurring(name: "Affitto", amount: 500, categoryName: "Casa e bollette", day: 1, nextKey: "2026-11")]
        XCTAssertEqual(everydaySpend(cena, recurring: rec), 40, "Conta solo la mia parte")
        XCTAssertEqual(everydaySpend(affitto, recurring: rec), 0, "L'affitto non è una spesa di tutti i giorni")
        XCTAssertEqual(everydaySpend(Expense(amount: 12, categoryName: "Altro", date: Date(), note: "x"), recurring: rec), 12)
    }

    func testRicorrentiInArrivoNellaPrevisione() {
        let rec = [Recurring(name: "Netflix", amount: 13.99, categoryName: "Svago", day: 20, nextKey: "2026-10"),
                   Recurring(name: "Affitto", amount: 500, categoryName: "Casa e bollette", day: 1, nextKey: "2026-11")]
        let up = upcomingRecurring(rec, before: day(2026, 10, 31, 0), now: day(2026, 10, 10))
        XCTAssertEqual(up, 13.99, accuracy: 0.001, "Solo quelle prima del prossimo stipendio")
        let f = makeForecast(available: 900, spent: 300, period: (day(2026, 10, 1, 0), day(2026, 10, 31, 0)),
                             upcoming: up, now: day(2026, 10, 10))
        XCTAssertEqual(f.projected, 900 - 13.99 - 30 * 21, accuracy: 0.001)
    }
}
