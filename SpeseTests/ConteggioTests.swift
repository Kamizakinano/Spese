import XCTest
@testable import Spese

/// Conteggio veloce: differenza tra saldo vero e saldo dell'app.
final class ConteggioTests: XCTestCase {
    func testDifferenza() {
        XCTAssertEqual(balanceDifference(real: "1369,73", app: 1402.46) ?? 0, -32.73, accuracy: 0.001)
        XCTAssertEqual(balanceDifference(real: "250", app: 250) ?? 1, 0, accuracy: 0.001)
        XCTAssertNil(balanceDifference(real: "", app: 10))
    }

    func testCorrezioneDellaCarta() {
        let base = [Income(amount: 1000, saved: 0, kind: "Stipendio", date: Date().addingTimeInterval(-60), note: "")]
        let l0 = Ledger(incomes: base, expenses: [], moves: [], cashMoves: [], start: .distantPast)
        let fix = Income(amount: -32.73, saved: 0, kind: balanceFixKind, date: Date(), note: "Conteggio veloce")
        let l1 = Ledger(incomes: base + [fix], expenses: [], moves: [], cashMoves: [], start: .distantPast)
        XCTAssertEqual(l1.figures(for: Date()).left - l0.figures(for: Date()).left, -32.73, accuracy: 0.001)
    }
}
