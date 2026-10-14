import XCTest
@testable import Spese

/// Prove di: il tuo anno in Spese, mappa delle spese.
final class AnnoMappaTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: 12))!
    }

    func testIlTuoAnno() {
        let ex = [
            Expense(amount: 10, categoryName: "Alimentari", date: d(2026, 3, 1), note: "Lidl"),
            Expense(amount: 12, categoryName: "Alimentari", date: d(2026, 3, 8), note: "lidl"),
            Expense(amount: 200, categoryName: "Viaggi", date: d(2026, 8, 1), note: "Volo"),
            Expense(amount: 99, categoryName: "Svago", date: d(2025, 12, 31), note: "Anno prima")
        ]
        let inc = [Income(amount: 1000, saved: 100, kind: "Stipendio", date: d(2026, 1, 10), note: "")]
        let r = yearRecap(year: 2026, expenses: ex, incomes: inc, moves: [SavingsMove(amount: 50, date: d(2026, 5, 1), note: "")],
                          now: d(2026, 12, 31))
        XCTAssertEqual(r.total, 222, accuracy: 0.001)
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.topCategory?.name, "Viaggi")
        XCTAssertEqual(r.topPlace?.name, "Lidl")
        XCTAssertEqual(r.topPlace?.times, 2)
        XCTAssertEqual(r.saved, 150, accuracy: 0.001)
        XCTAssertEqual(Calendar.current.component(.month, from: r.topMonth!.date), 8)
    }

    func testStagioneDelRiassunto() {
        XCTAssertNil(yearRecapSeason(d(2026, 12, 19)))
        XCTAssertEqual(yearRecapSeason(d(2026, 12, 20)), 2026)
        XCTAssertEqual(yearRecapSeason(d(2027, 1, 10)), 2026)
        XCTAssertNil(yearRecapSeason(d(2027, 1, 11)))
    }

    func testPostiSullaMappa() {
        func at(_ amount: Double, _ note: String, _ lat: Double, _ lon: Double) -> Expense {
            let e = Expense(amount: amount, categoryName: "Alimentari", date: d(2026, 10, 1), note: note)
            e.latitude = lat; e.longitude = lon
            return e
        }
        let places = spendPlaces([at(10, "Lidl", 37.50021, 15.08712), at(20, "Lidl", 37.50024, 15.08718),
                                  at(5, "Bar", 37.51, 15.09), Expense(amount: 99, categoryName: "Altro", date: d(2026, 10, 1), note: "")])
        XCTAssertEqual(places.count, 2, "Le spese senza luogo non vanno sulla mappa")
        XCTAssertEqual(places.first?.name, "Lidl")
        XCTAssertEqual(places.first?.total ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(places.first?.count, 2)
    }
}
