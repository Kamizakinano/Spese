import XCTest
@testable import Spese

/// La previsione toglie anche mutuo, ricorrenti e abbonamenti in arrivo prima dello stipendio.
final class PrevisioneRicorrentiTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    func testRicorrentiPrimaDelloStipendio() {
        let mutuo = Recurring(name: "Mutuo", amount: 650, categoryName: "Casa e bollette", day: 1, nextKey: "2026-11")
        let netflix = Recurring(name: "Netflix", amount: 13.99, categoryName: "Svago", day: 20, nextKey: "2026-10")
        let dopo = Recurring(name: "Palestra", amount: 40, categoryName: "Svago", day: 15, nextKey: "2026-11")
        let now = d(2026, 10, 17)
        let tot = recurringDue([mutuo, netflix, dopo], expenses: [], before: d(2026, 11, 9, 0), now: now)
        XCTAssertEqual(tot, 663.99, accuracy: 0.001, "Mutuo del 1° nov e Netflix del 20 ott sì, palestra del 15 nov no")

        // Il mutuo già inserito a mano non si conta due volte.
        let fatto = Expense(amount: 650, categoryName: "Casa e bollette", date: d(2026, 11, 1), note: "Mutuo")
        XCTAssertEqual(recurringDue([mutuo, netflix], expenses: [fatto], before: d(2026, 11, 9, 0), now: now), 13.99, accuracy: 0.001)
    }
}
