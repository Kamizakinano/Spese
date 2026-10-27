import XCTest
@testable import Spese

/// Prove del "Controllo di stasera" e delle barre per categoria (2.55).
final class ControlloSeraTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ g: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: g, hour: 12))!
    }

    func testTestoControlloSera() {
        XCTAssertEqual(eveningCheckText([]), "Oggi non hai segnato spese. Hai pagato qualcosa? Tocca per controllare.")
        let today = [Expense(amount: 24.5, categoryName: "Spesa", date: Date(), note: "Esselunga"),
                     Expense(amount: 13.7, categoryName: "Bar", date: Date(), note: "Bar")]
        XCTAssertTrue(eveningCheckText(today).hasPrefix("Oggi hai segnato 2 spese, "))
        XCTAssertTrue(eveningCheckText(Array(today.prefix(1))).hasPrefix("Oggi hai segnato 1 spesa, "))
    }

    func testBarrePerCategoria() {
        let now = d(2026, 10, 26)
        let ex = [Expense(amount: 50, categoryName: "Spesa", date: d(2026, 10, 3), note: ""),
                  Expense(amount: 120, categoryName: "Casa", date: d(2026, 10, 10), note: ""),
                  Expense(amount: 40, categoryName: "Spesa", date: d(2026, 9, 5), note: ""),
                  Expense(amount: 30, categoryName: "Auto", date: d(2026, 9, 6), note: "")]
        let bars = categoryBars(ex, scale: .mese, now: now, payDay: nil)
        XCTAssertEqual(bars.map(\.name), ["Casa", "Spesa"], "Dalla più alta, solo categorie con spese nel mese")
        XCTAssertEqual(bars.last?.before, 40)
        XCTAssertNil(bars.first?.percent, "Casa è nuova rispetto al mese scorso")
        XCTAssertEqual(categoryBars(ex, scale: .anno, now: now, payDay: nil).reduce(0) { $0 + $1.now }, 240)
    }
}
