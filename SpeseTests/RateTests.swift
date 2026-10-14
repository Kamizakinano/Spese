import XCTest
@testable import Spese

/// Prove dei pagamenti a rate (PayPal, Klarna).
final class RateTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: hour))!
    }

    func testTreRateUnaAlMese() {
        let s = installmentSchedule(total: 85.80, count: 3, paid: 0, first: d(2026, 10, 15))
        XCTAssertEqual(s.map(\.index), [1, 2, 3])
        XCTAssertEqual(s.map(\.amount), [28.60, 28.60, 28.60])
        XCTAssertEqual(s.map(\.date), [d(2026, 10, 15), d(2026, 11, 15), d(2026, 12, 15)])
    }

    func testRateGiaPagateEArrotondamento() {
        let s = installmentSchedule(total: 100, count: 3, paid: 1, first: d(2026, 10, 20))
        XCTAssertEqual(s.map(\.index), [2, 3], "La rata già pagata non si crea")
        XCTAssertEqual(s[0].amount, 33.33, accuracy: 0.001)
        XCTAssertEqual(s[1].amount, 33.34, accuracy: 0.001, "L'ultima assorbe i centesimi")
        XCTAssertTrue(installmentSchedule(total: 100, count: 3, paid: 3, first: d(2026, 10, 20)).isEmpty)
    }

    func testQuantoMancaAllaFine() {
        let rates = makeInstallments(total: 250, count: 4, paid: 1, first: d(2026, 10, 10), name: "Divano", provider: "Klarna")
        XCTAssertEqual(rates.count, 3)
        XCTAssertTrue(rates.allSatisfy { $0.categoryRaw == installmentCategory && $0.planProvider == "Klarna" })
        XCTAssertEqual(rates.first?.note, "Divano · rata 2 di 4")
        let p = installmentPlans(rates, now: d(2026, 10, 13)).first
        XCTAssertEqual(p?.paidCount, 2, "Una pagata prima + quella del 10 ottobre")
        XCTAssertEqual(p?.remainingCount, 2)
        XCTAssertEqual(p?.remaining ?? 0, 125, accuracy: 0.001)
        XCTAssertEqual(p?.end, d(2026, 12, 10))
        XCTAssertEqual(p?.next?.planIndex, 3)
    }

    func testTotaliPerPayPalEKlarna() {
        let ex = makeInstallments(total: 60, count: 2, paid: 0, first: d(2026, 10, 1), name: "A", provider: "PayPal")
            + makeInstallments(total: 40, count: 2, paid: 0, first: d(2026, 10, 1), name: "B", provider: "Klarna")
            + [Expense(amount: 9, categoryName: "Svago", date: d(2026, 10, 1), note: "")]
        let t = installmentProviderTotals(ex)
        XCTAssertEqual(t.map(\.name), ["PayPal", "Klarna"])
        XCTAssertEqual(t.first?.total ?? 0, 60, accuracy: 0.001)
    }

    func testCategoriaPrimaDiAltro() {
        XCTAssertTrue(defaultCategories.contains { $0.0 == installmentCategory })
        XCTAssertEqual(defaultCategories.last?.0, "Altro")
    }
}

final class RateModificaTests: XCTestCase {
    func testCambiareCosaHaiCompratoAggiornaTutteLeRate() {
        let rates = makeInstallments(total: 90, count: 3, paid: 0, first: Date(), name: "Zalando", provider: "PayPal")
        updateInstallmentPlan(rates, name: " Scarpe ", provider: "Klarna")
        XCTAssertEqual(rates.map(\.note), ["Scarpe · rata 1 di 3", "Scarpe · rata 2 di 3", "Scarpe · rata 3 di 3"])
        XCTAssertTrue(rates.allSatisfy { $0.planName == "Scarpe" && $0.planProvider == "Klarna" })
        updateInstallmentPlan(rates, name: "  ", provider: "Klarna")
        XCTAssertEqual(rates.first?.planName, "Scarpe", "Un nome vuoto non cancella quello di prima")
    }
}
